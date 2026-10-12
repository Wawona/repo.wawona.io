//! Shared helpers for minimal WASI P1 CLI ports.
use std::io::{self, BufRead, Read, Write};

pub fn stdin_to_string() -> io::Result<String> {
    let mut s = String::new();
    io::stdin().read_to_string(&mut s)?;
    Ok(s)
}

pub fn stdin_lines() -> io::Result<Vec<String>> {
    io::stdin().lock().lines().collect()
}

pub fn write_stdout(s: &str) {
    let _ = io::stdout().write_all(s.as_bytes());
}

pub fn writeln_stdout(s: &str) {
    let mut out = io::stdout().lock();
    let _ = writeln!(out, "{s}");
}
