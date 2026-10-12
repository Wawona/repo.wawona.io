//! Byte-for-byte compatibility against the reference `phoon` output corpus in
//! `tests/reference/` (captured with `TZ=UTC`; see `tools/gen-corpus.sh`).

use std::fs;
use std::path::PathBuf;

use phoon_rs::render;

fn reference_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/reference")
}

#[test]
fn reference_corpus_is_reproduced_byte_for_byte() {
    let manifest = include_str!("reference/manifest.txt");
    let dir = reference_dir();
    let mut checked = 0usize;

    for line in manifest.lines() {
        let line = line.trim_end();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut it = line.split('\t');
        let name = it.next().expect("name");
        let size: i32 = it.next().expect("size").parse().expect("size int");
        let t: i64 = it.next().expect("time").parse().expect("time int");
        let clock: i64 = it.next().expect("clock").parse().expect("clock int");

        let expected = fs::read(dir.join(format!("{name}.txt")))
            .unwrap_or_else(|e| panic!("read fixture {name}: {e}"));
        let got = render::render_bytes(t, size, clock);

        assert_eq!(
            got, expected,
            "fixture `{name}` differs (numlines={size}, t={t}, clock={clock})"
        );
        checked += 1;
    }

    assert!(checked > 20, "expected a populated corpus, got {checked}");
}
