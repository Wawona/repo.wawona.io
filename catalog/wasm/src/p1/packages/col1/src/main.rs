//! Minimal WASI P1 awk: `{print $1}` on stdin.
use std::env;
use std::io::{self, BufRead, Write};
use std::process;

fn main() {
    let prog = env::args().nth(1).unwrap_or_else(|| {
        eprintln!("awk: program required");
        process::exit(2);
    });
    if prog != "{print $1}" {
        eprintln!("awk: only {{print $1}} is supported in this WASI P1 port");
        process::exit(2);
    }
    let stdin = io::stdin();
    let mut out = io::stdout().lock();
    for line in stdin.lock().lines() {
        let line = line.unwrap_or_default();
        let field = line.split_whitespace().next().unwrap_or("");
        writeln!(out, "{field}").ok();
    }
}
