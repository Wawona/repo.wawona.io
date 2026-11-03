//! WASI P1 Wayland registry honesty probe for Wawona Runtime.
//!
//! Connects through the host ABI, dumps globals, diffs against an embedded
//! per-profile expect set, and runs shallow smokes for store-safe core
//! globals. Emits NDJSON on stdout.
//!
//! Exit codes:
//!   0 ok · 1 missing required · 2 unexpected · 3 smoke failed · 4 connect/ABI
//!
//! `--self-check` validates embedded expects without a compositor (Wasmtime smoke).

use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::io::{self, Write};
use std::process;
use std::thread;
use std::time::Duration;

#[cfg(feature = "host-abi")]
#[link(wasm_import_module = "env")]
extern "C" {
    fn wawona_wayland_connect(fd_out: *mut i32) -> i32;
    fn wawona_wayland_sendmsg(wl_fd: i32, buf: *const u8, len: i32, scm_fd: i32) -> i32;
    fn wawona_socket_recv(fd: i32, buf: *mut u8, len: i32, n_out: *mut i32) -> i32;
}

#[cfg(not(feature = "host-abi"))]
unsafe fn wawona_wayland_connect(fd_out: *mut i32) -> i32 {
    *fd_out = -1;
    -1
}

#[cfg(not(feature = "host-abi"))]
unsafe fn wawona_wayland_sendmsg(_wl_fd: i32, _buf: *const u8, _len: i32, _scm_fd: i32) -> i32 {
    -1
}

#[cfg(not(feature = "host-abi"))]
unsafe fn wawona_socket_recv(_fd: i32, _buf: *mut u8, _len: i32, _n_out: *mut i32) -> i32 {
    -1
}

const DISPLAY: u32 = 1;

const STORE_SAFE: &str = include_str!("../expect/store-safe.json");
const STORE_SAFE_REMOTE: &str = include_str!("../expect/store-safe-remote.json");
const DESKTOP_HOST: &str = include_str!("../expect/desktop-host.json");
const FULL_DEV: &str = include_str!("../expect/full-dev.json");

const SMOKE_GLOBALS: &[&str] = &["wl_compositor", "wl_shm", "wl_seat", "xdg_wm_base"];

#[derive(Debug, Clone)]
struct ExpectFile {
    profile: String,
    required: BTreeSet<String>,
    optional: BTreeMap<String, String>,
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let self_check = args.iter().any(|a| a == "--self-check");
    let human = args.iter().any(|a| a == "--human");
    let profile = env::var("WAWONA_PROTOCOL_PROFILE").unwrap_or_else(|_| "store-safe".into());

    let expect = match load_expect(&profile) {
        Ok(e) => e,
        Err(err) => {
            eprintln!("protocol-probe: {err}");
            process::exit(4);
        }
    };

    if self_check {
        emit_json(&format!(
            "{{\"event\":\"self_check\",\"profile\":\"{}\",\"required\":{},\"optional\":{},\"result\":\"ok\"}}",
            expect.profile,
            expect.required.len(),
            expect.optional.len()
        ));
        if human {
            eprintln!(
                "self-check ok profile={} required={} optional={}",
                expect.profile,
                expect.required.len(),
                expect.optional.len()
            );
        }
        println!("protocol-probe self-check ok");
        process::exit(0);
    }

    let mut wl = 0i32;
    let rc = unsafe { wawona_wayland_connect(&mut wl) };
    if rc != 0 {
        eprintln!("protocol-probe: wayland connect errno={rc} (is WAYLAND_DISPLAY set?)");
        process::exit(4);
    }

    let mut conn = Conn::new(wl);
    conn.sync_registry();

    let advertised: BTreeSet<String> = conn.globals.keys().cloned().collect();
    let mut missing = 0usize;
    let mut unexpected = 0usize;
    let mut smokes_failed = 0usize;

    for iface in &expect.required {
        let present = advertised.contains(iface);
        let result = if present { "ok" } else { "missing" };
        if !present {
            missing += 1;
        }
        let ver_json = conn
            .globals
            .get(iface)
            .map(|v| v.to_string())
            .unwrap_or_else(|| "null".into());
        emit_json(&format!(
            "{{\"event\":\"global\",\"interface\":\"{iface}\",\"version\":{ver_json},\"expect\":\"required\",\"result\":\"{result}\"}}"
        ));
    }

    for (iface, cap) in &expect.optional {
        let present = advertised.contains(iface);
        let result = if present { "ok" } else { "absent_ok" };
        let ver_json = conn
            .globals
            .get(iface)
            .map(|v| v.to_string())
            .unwrap_or_else(|| "null".into());
        emit_json(&format!(
            "{{\"event\":\"global\",\"interface\":\"{iface}\",\"version\":{ver_json},\"expect\":\"optional\",\"capability\":\"{cap}\",\"result\":\"{result}\"}}"
        ));
    }

    for iface in &advertised {
        if expect.required.contains(iface) || expect.optional.contains_key(iface) {
            continue;
        }
        unexpected += 1;
        let ver = conn.globals[iface];
        emit_json(&format!(
            "{{\"event\":\"global\",\"interface\":\"{iface}\",\"version\":{ver},\"expect\":\"none\",\"result\":\"unexpected\"}}"
        ));
    }

    for iface in SMOKE_GLOBALS {
        if !advertised.contains(*iface) {
            emit_json(&format!(
                "{{\"event\":\"smoke\",\"interface\":\"{iface}\",\"result\":\"skipped\"}}"
            ));
            continue;
        }
        match conn.smoke_bind_destroy(iface) {
            Ok(()) => emit_json(&format!(
                "{{\"event\":\"smoke\",\"interface\":\"{iface}\",\"result\":\"ok\"}}"
            )),
            Err(err) => {
                smokes_failed += 1;
                emit_json(&format!(
                    "{{\"event\":\"smoke\",\"interface\":\"{iface}\",\"result\":\"fail\",\"detail\":{}}}",
                    json_string(&err)
                ));
            }
        }
    }

    emit_json(&format!(
        "{{\"event\":\"summary\",\"profile\":\"{}\",\"advertised\":{},\"missing\":{},\"unexpected\":{},\"smokes_failed\":{}}}",
        expect.profile,
        advertised.len(),
        missing,
        unexpected,
        smokes_failed
    ));

    if human {
        eprintln!(
            "profile={} advertised={} missing={} unexpected={} smokes_failed={}",
            expect.profile,
            advertised.len(),
            missing,
            unexpected,
            smokes_failed
        );
    }

    if missing > 0 {
        process::exit(1);
    }
    if unexpected > 0 {
        process::exit(2);
    }
    if smokes_failed > 0 {
        process::exit(3);
    }
    process::exit(0);
}

fn load_expect(profile: &str) -> Result<ExpectFile, String> {
    let raw = match profile {
        "store-safe" => STORE_SAFE,
        "store-safe-remote" => STORE_SAFE_REMOTE,
        "desktop-host" => DESKTOP_HOST,
        "full-dev" => FULL_DEV,
        other => return Err(format!("unknown profile {other}")),
    };
    parse_expect(raw)
}

fn parse_expect(raw: &str) -> Result<ExpectFile, String> {
    let profile = extract_string_field(raw, "profile").unwrap_or_else(|| "unknown".into());
    let required = extract_string_array(raw, "required")?;
    let optional = extract_optional_array(raw)?;
    Ok(ExpectFile {
        profile,
        required: required.into_iter().collect(),
        optional: optional.into_iter().collect(),
    })
}

fn extract_string_field(raw: &str, key: &str) -> Option<String> {
    let needle = format!("\"{key}\"");
    let idx = raw.find(&needle)?;
    let after = &raw[idx + needle.len()..];
    let colon = after.find(':')?;
    let rest = after[colon + 1..].trim_start();
    if !rest.starts_with('"') {
        return None;
    }
    let end = rest[1..].find('"')?;
    Some(rest[1..1 + end].to_string())
}

fn extract_string_array(raw: &str, key: &str) -> Result<Vec<String>, String> {
    let needle = format!("\"{key}\"");
    let idx = raw
        .find(&needle)
        .ok_or_else(|| format!("missing {key}"))?;
    let after = &raw[idx + needle.len()..];
    let start = after
        .find('[')
        .ok_or_else(|| format!("missing [ for {key}"))?;
    let body = &after[start + 1..];
    let end = body
        .find(']')
        .ok_or_else(|| format!("missing ] for {key}"))?;
    let slice = &body[..end];
    let mut out = Vec::new();
    let mut chars = slice.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '"' {
            continue;
        }
        let mut s = String::new();
        for ch in chars.by_ref() {
            if ch == '"' {
                break;
            }
            s.push(ch);
        }
        if !s.is_empty() {
            out.push(s);
        }
    }
    Ok(out)
}

fn extract_optional_array(raw: &str) -> Result<Vec<(String, String)>, String> {
    let idx = raw.find("\"optional\"").ok_or("missing optional")?;
    let after = &raw[idx..];
    let start = after.find('[').ok_or("missing [ for optional")?;
    let body = &after[start + 1..];
    let end = body.find(']').ok_or("missing ] for optional")?;
    let slice = &body[..end];
    let mut out = Vec::new();
    for obj in slice.split('{').skip(1) {
        let iface = obj
            .split("\"interface\"")
            .nth(1)
            .and_then(|s| s.split('"').nth(1))
            .unwrap_or("")
            .to_string();
        let cap = obj
            .split("\"capability\"")
            .nth(1)
            .and_then(|s| s.split('"').nth(1))
            .unwrap_or("")
            .to_string();
        if !iface.is_empty() {
            out.push((iface, cap));
        }
    }
    Ok(out)
}

fn emit_json(line: &str) {
    let _ = writeln!(io::stdout(), "{line}");
}

fn json_string(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            _ => out.push(c),
        }
    }
    out.push('"');
    out
}

struct Conn {
    wl: i32,
    next_id: u32,
    registry: u32,
    globals: BTreeMap<String, u32>,
    names: BTreeMap<u32, (String, u32)>,
    rx: Vec<u8>,
}

impl Conn {
    fn new(wl: i32) -> Self {
        Self {
            wl,
            next_id: 2,
            registry: 0,
            globals: BTreeMap::new(),
            names: BTreeMap::new(),
            rx: Vec::new(),
        }
    }

    fn alloc(&mut self) -> u32 {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    fn req(&self, obj: u32, opcode: u16, body: &[u8]) {
        let mut msg = Vec::new();
        put_header(&mut msg, obj, opcode, 8 + body.len() as u32);
        msg.extend_from_slice(body);
        let rc = unsafe { wawona_wayland_sendmsg(self.wl, msg.as_ptr(), msg.len() as i32, -1) };
        if rc != 0 {
            eprintln!("protocol-probe: sendmsg errno={rc}");
        }
    }

    fn sync_registry(&mut self) {
        self.registry = self.alloc();
        self.req(DISPLAY, 1, &self.registry.to_le_bytes());
        let cb = self.alloc();
        self.req(DISPLAY, 0, &cb.to_le_bytes());
        let mut done = false;
        let mut spins = 0u32;
        while !done {
            match self.read_event() {
                Some((obj, opcode, payload)) => {
                    spins = 0;
                    if obj == cb && opcode == 0 {
                        done = true;
                    } else if obj == self.registry && opcode == 0 {
                        self.on_global(&payload);
                    }
                }
                None => {
                    spins += 1;
                    if spins > 5000 {
                        eprintln!("protocol-probe: registry sync timed out");
                        break;
                    }
                    thread::sleep(Duration::from_millis(2));
                }
            }
        }
    }

    fn on_global(&mut self, payload: &[u8]) {
        if payload.len() < 8 {
            return;
        }
        let name = u32::from_le_bytes(payload[0..4].try_into().unwrap());
        let (iface, rest) = take_string(&payload[4..]);
        if rest.len() < 4 {
            return;
        }
        let version = u32::from_le_bytes(rest[0..4].try_into().unwrap());
        self.globals.insert(iface.clone(), version);
        self.names.insert(name, (iface, version));
    }

    fn smoke_bind_destroy(&mut self, iface: &str) -> Result<(), String> {
        let (name, version) = self
            .names
            .iter()
            .find(|(_, (i, _))| i == iface)
            .map(|(n, (_, v))| (*n, *v))
            .ok_or_else(|| format!("{iface} not in registry names"))?;

        let id = self.alloc();
        let mut body = Vec::new();
        body.extend_from_slice(&name.to_le_bytes());
        put_string(&mut body, iface);
        let ver = match iface {
            "wl_compositor" => version.min(6),
            "wl_shm" => 1,
            "wl_seat" => version.min(9),
            "xdg_wm_base" => version.min(6),
            _ => version.min(1),
        };
        body.extend_from_slice(&ver.to_le_bytes());
        body.extend_from_slice(&id.to_le_bytes());
        self.req(self.registry, 0, &body);

        match iface {
            "wl_seat" if ver >= 5 => self.req(id, 0, &[]),
            "xdg_wm_base" => self.req(id, 0, &[]),
            _ => {}
        }
        Ok(())
    }

    fn read_event(&mut self) -> Option<(u32, u16, Vec<u8>)> {
        while self.rx.len() < 8 {
            if !self.pump() {
                return None;
            }
        }
        let hdr = &self.rx[..8];
        let obj = u32::from_le_bytes(hdr[0..4].try_into().unwrap());
        let size_op = u32::from_le_bytes(hdr[4..8].try_into().unwrap());
        let size = (size_op >> 16) as usize;
        let opcode = (size_op & 0xffff) as u16;
        if size < 8 {
            return None;
        }
        while self.rx.len() < size {
            if !self.pump() {
                return None;
            }
        }
        let payload = self.rx[8..size].to_vec();
        self.rx.drain(..size);
        Some((obj, opcode, payload))
    }

    fn pump(&mut self) -> bool {
        let mut buf = [0u8; 4096];
        let mut n_out = 0i32;
        let rc =
            unsafe { wawona_socket_recv(self.wl, buf.as_mut_ptr(), buf.len() as i32, &mut n_out) };
        if rc != 0 || n_out <= 0 {
            return false;
        }
        self.rx.extend_from_slice(&buf[..n_out as usize]);
        true
    }
}

fn put_header(out: &mut Vec<u8>, obj: u32, opcode: u16, size: u32) {
    out.extend_from_slice(&obj.to_le_bytes());
    let size_op = (size << 16) | u32::from(opcode);
    out.extend_from_slice(&size_op.to_le_bytes());
}

fn put_string(out: &mut Vec<u8>, s: &str) {
    let bytes = s.as_bytes();
    let n = bytes.len() + 1;
    out.extend_from_slice(&(n as u32).to_le_bytes());
    out.extend_from_slice(bytes);
    out.push(0);
    while out.len() % 4 != 0 {
        out.push(0);
    }
}

fn take_string(data: &[u8]) -> (String, &[u8]) {
    if data.len() < 4 {
        return (String::new(), data);
    }
    let n = u32::from_le_bytes(data[0..4].try_into().unwrap()) as usize;
    let padded = n.div_ceil(4) * 4;
    if data.len() < 4 + padded {
        return (String::new(), &[]);
    }
    let raw = &data[4..4 + n.saturating_sub(1)];
    let s = String::from_utf8_lossy(raw).into_owned();
    (s, &data[4 + padded..])
}
