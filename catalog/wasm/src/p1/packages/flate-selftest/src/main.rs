//! Minimal WASI P1 gzip: `--self-test` round-trips a buffer via flate2.
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use flate2::Compression;
use std::env;
use std::io::{Read, Write};
use std::process;

fn main() {
    let arg = env::args().nth(1).unwrap_or_default();
    if arg != "--self-test" {
        eprintln!("gzip: only --self-test is supported in this WASI P1 port");
        process::exit(2);
    }
    let payload = b"wawona-gzip-self-test";
    let mut enc = GzEncoder::new(Vec::new(), Compression::default());
    enc.write_all(payload).expect("encode write");
    let compressed = enc.finish().expect("encode finish");
    let mut dec = GzDecoder::new(&compressed[..]);
    let mut out = Vec::new();
    dec.read_to_end(&mut out).expect("decode");
    if out.as_slice() != payload {
        eprintln!("gzip: self-test mismatch");
        process::exit(1);
    }
    println!("ok");
}
