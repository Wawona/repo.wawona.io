//! Minimal WASI P1 sed: `s/old/new/` once per line on stdin.
use std::env;
use std::io::{self, BufRead, Write};
use std::process;

fn parse_s(expr: &str) -> Option<(String, String)> {
    let expr = expr.strip_prefix('s')?;
    let delim = expr.chars().next()?;
    let rest = &expr[delim.len_utf8()..];
    let mut parts = rest.split(delim);
    let old = parts.next()?.to_string();
    let new = parts.next()?.to_string();
    Some((old, new))
}

fn main() {
    let expr = env::args().nth(1).unwrap_or_else(|| {
        eprintln!("sed: expression required");
        process::exit(2);
    });
    let (old, new) = parse_s(&expr).unwrap_or_else(|| {
        eprintln!("sed: only s/// is supported in this WASI P1 port");
        process::exit(2);
    });
    let stdin = io::stdin();
    let mut out = io::stdout().lock();
    for line in stdin.lock().lines() {
        let line = line.unwrap_or_default();
        writeln!(out, "{}", line.replacen(&old, &new, 1)).ok();
    }
}
