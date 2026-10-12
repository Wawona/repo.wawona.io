//! Dev-only generator: reconstruct `phoon`'s ASCII background frames from a
//! reference binary's *stdout* (never from its source arrays), then write them
//! to `src/data/*.txt` for the renderer to overlay the terminator onto.
//!
//! This is the "output as compatibility fixture" approach: for each templated
//! size we sample the reference across a full lunation and, using our own
//! terminator geometry to know which columns are lit in each frame, copy the lit
//! cell's character. Every ever-lit cell is thereby recovered from observed
//! output; cells that are never lit are always printed as spaces by both
//! programs, so leaving them blank is exact.
//!
//! Requires a reference `phoon` binary via `PHOON_REF` and (on macOS) a
//! `time()`-fixing interpose dylib via `PHOON_FIXTIME` so the wall-clock easter
//! eggs are deterministic. Run:
//!
//! ```sh
//! PHOON_REF=/path/to/phoon PHOON_FIXTIME=/path/to/fixtime.dylib \
//!   cargo run --features oracle-tools --bin gen-backgrounds
//! ```

use std::process::Command;

use phoon_rs::caltime::{self, gmtime, timegm};
use phoon_rs::geometry;
use phoon_rs::lunar;

const TEMPLATED: &[i32] = &[18, 19, 21, 22, 23, 24, 29, 32];
const MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

fn run_oracle(reff: &str, fixtime: Option<&str>, numlines: i32, t: i64, fake_now: i64) -> Vec<u8> {
    let tm = gmtime(t);
    let date = format!(
        "{} {} {} {:02}:{:02}:{:02}",
        tm.mday,
        MONTHS[(tm.mon - 1) as usize],
        tm.year,
        tm.hour,
        tm.min,
        tm.sec
    );
    let mut cmd = Command::new(reff);
    cmd.arg("-l").arg(numlines.to_string()).arg(&date);
    cmd.env("TZ", "UTC");
    cmd.env("FAKE_NOW", fake_now.to_string());
    if let Some(fx) = fixtime {
        cmd.env("DYLD_INSERT_LIBRARIES", fx);
        cmd.env("DYLD_FORCE_FLAT_NAMESPACE", "1");
    }
    let out = cmd.output().expect("failed to spawn reference phoon");
    out.stdout
}

/// Reconstruct one frame grid (numlines x 2*numlines bytes).
fn reconstruct(
    reff: &str,
    fixtime: Option<&str>,
    numlines: i32,
    base: i64,
    days: i64,
    fake_now_for: &dyn Fn(i64) -> i64,
) -> Vec<Vec<u8>> {
    // The canned arrays are [N][2N+1] and fully filled (no NUL terminator), so
    // the rightmost drawable column is index 2N. Reconstruct at that width.
    let ncols = (2 * numlines + 1) as usize;
    let mut grid = vec![vec![b' '; ncols]; numlines as usize];
    let step: i64 = 3600; // 1 hour; edges move slowly so this over-covers
    let count = days * 86400 / step;
    for i in 0..count {
        let t = base + i * step;
        if t.rem_euclid(17) == 3 {
            continue; // avoid GREENCHEESE filler; we want '@' to mean "lit"
        }
        let fake_now = fake_now_for(t);
        let out = run_oracle(reff, fixtime, numlines, t, fake_now);
        let lines: Vec<&[u8]> = out.split(|&b| b == b'\n').collect();
        let pctphase = lunar::phase(lunar::unix_to_julian(t)).pctphase;
        for lin in 0..numlines {
            let span = geometry::line_span(numlines, lin, pctphase);
            let line = lines.get(lin as usize).copied().unwrap_or(&[][..]);
            let mut col = span.colleft.max(0);
            while col <= span.colright {
                if (col as usize) < ncols {
                    let ch = line.get(col as usize).copied().unwrap_or(b' ');
                    grid[lin as usize][col as usize] = ch;
                }
                col += 1;
            }
        }
    }
    grid
}

fn write_frame(name: &str, grid: &[Vec<u8>]) {
    let mut bytes = Vec::new();
    for row in grid {
        bytes.extend_from_slice(row);
        bytes.push(b'\n');
    }
    let path = format!("src/data/{name}.txt");
    std::fs::write(&path, &bytes).unwrap_or_else(|e| panic!("write {path}: {e}"));
    println!("wrote {path} ({} rows)", grid.len());
}

fn main() {
    let reff = std::env::var("PHOON_REF").expect("set PHOON_REF to a reference phoon binary");
    let fixtime = std::env::var("PHOON_FIXTIME").ok();
    let fx = fixtime.as_deref();

    // A base near a new moon so a ~31-day sweep covers a full lunation.
    let base = timegm(2000, 1, 1, 0, 30, 0);
    let days = 31;
    let fixed = |_t: i64| 1_000_000_000i64; // no easter eggs

    for &n in TEMPLATED {
        let name = format!("bg{n}");
        let grid = reconstruct(&reff, fx, n, base, days, &fixed);
        write_frame(&name, &grid);
    }

    // hubert29: FAKE_NOW=3 makes every size-29 frame render the Hubert variant.
    {
        let grid = reconstruct(&reff, fx, 29, base, days, &|_t| 3);
        write_frame("hubert29", &grid);
    }

    // pumpkin19: only in October, and only when clocknow % (33 - mday) == 1.
    // Pick a per-sample FAKE_NOW that satisfies that (and avoids the hubert
    // cheat, which needs FAKE_NOW % 13 == 3).
    {
        let oct_base = timegm(2001, 10, 1, 0, 30, 0);
        let pumpkin_now = |t: i64| -> i64 {
            let tm = caltime::gmtime(t);
            let div = 33 - tm.mday as i64; // 2..=32
            let mut v = div + 1; // v % div == 1
            while v % 13 == 3 {
                v += div;
            }
            v
        };
        let grid = reconstruct(&reff, fx, 19, oct_base, 30, &pumpkin_now);
        write_frame("pumpkin19", &grid);
    }

    println!("done");
}
