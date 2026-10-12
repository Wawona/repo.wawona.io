//! Minimal WASI P1 jq: `jq -n EXPR` prints a JSON literal.
use std::env;
use std::io::{self, Write};
use std::process;

fn main() {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("-n") => {
            let expr = args.next().unwrap_or_else(|| {
                eprintln!("jq: -n requires an expression");
                process::exit(2);
            });
            let value: serde_json::Value = serde_json::from_str(&expr).unwrap_or_else(|e| {
                eprintln!("jq: parse error: {e}");
                process::exit(1);
            });
            let mut out = io::stdout().lock();
            writeln!(out, "{value}").ok();
        }
        other => {
            eprintln!(
                "jq: only -n EXPR is supported in this WASI P1 port (got {:?})",
                other
            );
            process::exit(2);
        }
    }
}
