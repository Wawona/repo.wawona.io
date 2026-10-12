//! ASCII moon renderer: overlays the terminator (from [`crate::geometry`]) onto
//! either a canned art frame or a plain filled disc, and appends the phase
//! caption. Byte-for-byte compatible with the historical `phoon` (`TZ=UTC`).

use std::sync::OnceLock;

use crate::caltime;
use crate::geometry;
use crate::lunar;

/// Labels for the most-recent principal phase (elapsed since), 15 columns wide.
const QLITS: [&[u8]; 4] = [
    b"New Moon +     ",
    b"First Quarter +",
    b"Full Moon +    ",
    b"Last Quarter + ",
];
/// Labels for the next principal phase (remaining until), 15 columns wide.
const NQLITS: [&[u8]; 4] = [
    b"New Moon -     ",
    b"First Quarter -",
    b"Full Moon -    ",
    b"Last Quarter - ",
];

/// Parsed art frames. These are the utility's public output frames, recovered
/// from observed stdout (see `tools/gen_backgrounds.rs`) and stored as data.
struct Frames {
    bg18: Vec<Vec<u8>>,
    bg19: Vec<Vec<u8>>,
    pumpkin19: Vec<Vec<u8>>,
    bg21: Vec<Vec<u8>>,
    bg22: Vec<Vec<u8>>,
    bg23: Vec<Vec<u8>>,
    bg24: Vec<Vec<u8>>,
    bg29: Vec<Vec<u8>>,
    hubert29: Vec<Vec<u8>>,
    bg32: Vec<Vec<u8>>,
}

fn parse_frame(s: &str) -> Vec<Vec<u8>> {
    s.lines().map(|l| l.as_bytes().to_vec()).collect()
}

fn frames() -> &'static Frames {
    static F: OnceLock<Frames> = OnceLock::new();
    F.get_or_init(|| Frames {
        bg18: parse_frame(include_str!("data/bg18.txt")),
        bg19: parse_frame(include_str!("data/bg19.txt")),
        pumpkin19: parse_frame(include_str!("data/pumpkin19.txt")),
        bg21: parse_frame(include_str!("data/bg21.txt")),
        bg22: parse_frame(include_str!("data/bg22.txt")),
        bg23: parse_frame(include_str!("data/bg23.txt")),
        bg24: parse_frame(include_str!("data/bg24.txt")),
        bg29: parse_frame(include_str!("data/bg29.txt")),
        hubert29: parse_frame(include_str!("data/hubert29.txt")),
        bg32: parse_frame(include_str!("data/bg32.txt")),
    })
}

/// Select the art frame (if any) for `numlines`, resolving the October pumpkin
/// and the Hubert variants exactly as the reference does from the wall clock.
fn select_frame(numlines: i32, t: i64, clocknow: i64) -> Option<&'static Vec<Vec<u8>>> {
    let f = frames();
    match numlines {
        18 => Some(&f.bg18),
        19 => {
            let tm = caltime::gmtime(t);
            if tm.mon == 10 && clocknow.rem_euclid(33 - tm.mday as i64) == 1 {
                Some(&f.pumpkin19)
            } else {
                Some(&f.bg19)
            }
        }
        21 => Some(&f.bg21),
        22 => Some(&f.bg22),
        23 => Some(&f.bg23),
        24 => Some(&f.bg24),
        29 => {
            if clocknow.rem_euclid(23) == 3 {
                Some(&f.hubert29)
            } else {
                Some(&f.bg29)
            }
        }
        32 => Some(&f.bg32),
        _ => None,
    }
}

#[inline]
fn bg_char(frame: &[Vec<u8>], lin: i32, col: i32) -> u8 {
    // Frames are 2N+1 wide (indices 0..=2N), matching the reference's fully
    // filled `[N][2N+1]` arrays, so every drawable column is in range.
    frame
        .get(lin as usize)
        .and_then(|row| row.get(col as usize))
        .copied()
        .unwrap_or(b' ')
}

fn put_seconds(out: &mut Vec<u8>, secs: i64) {
    let days = secs / 86_400;
    let mut s = secs - days * 86_400;
    let hours = s / 3600;
    s -= hours * 3600;
    let minutes = s / 60;
    s -= minutes * 60;
    out.extend_from_slice(format!("{days} {hours:>2}:{minutes:02}:{s:02}").as_bytes());
}

/// Render the moon for Unix time `t` at `numlines` lines, using `now` as the
/// pseudo-random wall clock (drives the Hubert/pumpkin/cheese easter eggs).
/// Returns the raw stdout bytes, terminated by a trailing newline per line.
pub fn render_bytes(t: i64, numlines: i32, now: i64) -> Vec<u8> {
    // "Pseudo-randomly decide what the moon is made of."
    let filler: &[u8] = if t.rem_euclid(17) == 3 {
        b"GREENCHEESE"
    } else {
        b"@"
    };

    let jd = lunar::unix_to_julian(t);
    let info = lunar::phase(jd);
    let pctphase = info.pctphase;
    let cphase = info.illum;

    let mut numlines = numlines;
    let mut clocknow = now;
    // "Randomly cheat and generate Hubert."
    if clocknow.rem_euclid(13) == 3 && cphase > 0.8 {
        numlines = 29;
        clocknow = 3;
    }

    let midlin = numlines / 2;
    let (phases, which) = lunar::phasehunt2(jd);
    let frame = select_frame(numlines, t, clocknow);

    let mut out = Vec::new();
    let mut atflridx = 0usize;

    for lin in 0..numlines {
        let span = geometry::line_span(numlines, lin, pctphase);
        let mut col = 0i32;
        while col < span.colleft {
            out.push(b' ');
            col += 1;
        }
        while col <= span.colright {
            let c = match frame {
                Some(f) => bg_char(f, lin, col),
                None => b'@',
            };
            if c != b'@' {
                out.push(c);
            } else {
                out.push(filler[atflridx]);
                atflridx = (atflridx + 1) % filler.len();
            }
            col += 1;
        }

        if numlines <= 27 {
            if lin == midlin - 2 {
                out.extend_from_slice(b"\t ");
                out.extend_from_slice(QLITS[which[0] as usize]);
            } else if lin == midlin - 1 {
                out.extend_from_slice(b"\t ");
                put_seconds(&mut out, ((jd - phases[0]) * lunar::SECS_PER_DAY) as i64);
            } else if lin == midlin {
                out.extend_from_slice(b"\t ");
                out.extend_from_slice(NQLITS[which[1] as usize]);
            } else if lin == midlin + 1 {
                out.extend_from_slice(b"\t ");
                put_seconds(&mut out, ((phases[1] - jd) * lunar::SECS_PER_DAY) as i64);
            }
        }

        out.push(b'\n');
    }

    out
}
