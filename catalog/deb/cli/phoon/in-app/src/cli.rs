//! Command-line front end, matching `phoon`'s argument handling and diagnostics:
//! `phoon [-l <lines>] [<date/time>]`.

use std::io::Write;

use crate::{dateparse, now_unix, render};

const DEFAULT_NUMLINES: i32 = 23;

/// The "current time" used for the display default and the pseudo-random
/// easter-egg clock. `PHOON_NOW` (Unix seconds) overrides the wall clock so
/// output is fully reproducible; this mirrors running the reference under a
/// fixed `time()` and is what the compatibility tests use.
fn effective_now() -> i64 {
    std::env::var("PHOON_NOW")
        .ok()
        .and_then(|s| s.trim().parse::<i64>().ok())
        .unwrap_or_else(now_unix)
}

/// sscanf("%d")-style leading-integer parse: optional sign then digits, trailing
/// characters ignored; `None` if no digits are present.
fn parse_leading_int(s: &str) -> Option<i32> {
    let b = s.as_bytes();
    let mut i = 0;
    while i < b.len() && (b[i] == b' ' || b[i] == b'\t') {
        i += 1;
    }
    let mut sign: i64 = 1;
    if i < b.len() && (b[i] == b'+' || b[i] == b'-') {
        if b[i] == b'-' {
            sign = -1;
        }
        i += 1;
    }
    let start = i;
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
    }
    if i == start {
        return None;
    }
    let v: i64 = s[start..i].parse().ok()?;
    Some((sign * v) as i32)
}

/// Run with an explicit argv (`args[0]` is the program name). Returns the
/// process exit code and writes the moon to stdout / diagnostics to stderr.
pub fn run(args: &[String]) -> i32 {
    let prog = args.first().map(String::as_str).unwrap_or("phoon");
    let usage = format!("usage:  {prog}  [-l <lines>]  [<date/time>]\n");

    let argc = args.len();
    let mut argn = 1usize;
    let mut numlines = DEFAULT_NUMLINES;

    // Optional -l flag.
    if argc.saturating_sub(argn) >= 1 && args[argn].starts_with('-') {
        if args[argn] != "-l" {
            let _ = std::io::stderr().write_all(usage.as_bytes());
            return 1;
        }
        if argc.saturating_sub(argn) < 2 {
            let _ = std::io::stderr().write_all(usage.as_bytes());
            return 1;
        }
        match parse_leading_int(&args[argn + 1]) {
            Some(n) => numlines = n,
            None => {
                let _ = std::io::stderr().write_all(usage.as_bytes());
                return 1;
            }
        }
        argn += 2;
    }

    let clock = effective_now();

    // Date/time: 0 args -> now; 1..=3 args -> joined and parsed.
    let remaining = argc - argn;
    let t: i64 = match remaining {
        0 => clock,
        1 | 2 | 3 => {
            let buf = args[argn..].join(" ");
            match dateparse::parse(&buf) {
                Some(v) if v > 0 => v,
                _ => {
                    let _ = write!(std::io::stderr(), "illegal date/time: {buf}\n");
                    return 1;
                }
            }
        }
        _ => {
            let _ = std::io::stderr().write_all(usage.as_bytes());
            return 1;
        }
    };

    let bytes = render::render_bytes(t, numlines, clock);
    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    let _ = lock.write_all(&bytes);
    let _ = lock.flush();
    0
}

/// Convenience entry point that reads `std::env::args`.
pub fn run_from_env() -> i32 {
    let args: Vec<String> = std::env::args().collect();
    run(&args)
}
