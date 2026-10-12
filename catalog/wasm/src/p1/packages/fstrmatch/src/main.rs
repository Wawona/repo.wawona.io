//! Minimal WASI P1 grep: fixed-string match on stdin lines.
use std::env;
use std::io::{self, BufRead, Write};
use std::process;

fn main() {
    let pattern = env::args().nth(1).unwrap_or_else(|| {
        eprintln!("grep: PATTERN required");
        process::exit(2);
    });
    let stdin = io::stdin();
    let mut matched = false;
    let mut out = io::stdout().lock();
    for line in stdin.lock().lines() {
        let line = line.unwrap_or_default();
        if line.contains(&pattern) {
            writeln!(out, "{line}").ok();
            matched = true;
        }
    }
    if !matched {
        process::exit(1);
    }
}
