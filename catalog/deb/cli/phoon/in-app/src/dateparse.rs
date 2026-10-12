//! A behavioral date parser for the flexible `[<date/time>]` argument.
//!
//! The historical `phoon` fed its argument to a large `date_parse()` routine.
//! Rather than reproduce that routine, this parser was written from the
//! reference program's *observed* accept/reject behavior and returns the same
//! UTC timestamps for the supported forms; unsupported input returns `None`, so
//! the CLI prints the identical `illegal date/time:` diagnostic.
//!
//! Supported (order-independent day / month / year plus optional `HH:MM[:SS]`):
//!   `6 Jan 2000`, `6 Jan 2000 12:00:00`, `6-jan-2000 12:34:56`,
//!   `Jan 6 12:00:00 2000`, `12:00:00 6 Jan 2000`, `Thu Jan 6 12:00:00 2000`.
//!
//! All times are interpreted in UTC (see [`crate::caltime`]).

use crate::caltime;

const MONTHS: [&str; 12] = [
    "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
];
const WEEKDAYS: [&str; 7] = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];

#[derive(Default)]
struct Parts {
    day: Option<u32>,
    mon: Option<u32>,
    year: Option<i64>,
    hour: Option<u32>,
    min: Option<u32>,
    sec: Option<u32>,
    ampm: Option<bool>, // Some(true) = pm
}

fn month_index(tok: &str) -> Option<u32> {
    if tok.len() < 3 {
        return None;
    }
    let head = &tok[..3];
    MONTHS.iter().position(|m| *m == head).map(|i| i as u32 + 1)
}

fn is_weekday(tok: &str) -> bool {
    tok.len() >= 3 && WEEKDAYS.contains(&&tok[..3])
}

fn parse_time(tok: &str) -> Option<(u32, u32, u32)> {
    let mut it = tok.split(':');
    let h = it.next()?.parse::<u32>().ok()?;
    let m = it.next()?.parse::<u32>().ok()?;
    let s = match it.next() {
        Some(x) => x.parse::<u32>().ok()?,
        None => 0,
    };
    if it.next().is_some() || m > 59 || s > 59 {
        return None;
    }
    Some((h, m, s))
}

/// Parse a joined date/time string to a Unix timestamp (UTC), or `None` if the
/// form is not recognized.
pub fn parse(input: &str) -> Option<i64> {
    let lower = input.to_ascii_lowercase();

    // Split on whitespace and commas; expand '-' separated date groups.
    let mut tokens: Vec<String> = Vec::new();
    for raw in lower.split(|c: char| c.is_whitespace() || c == ',') {
        if raw.is_empty() {
            continue;
        }
        if raw.contains('-') && !raw.contains(':') {
            for part in raw.split('-') {
                if !part.is_empty() {
                    tokens.push(part.to_string());
                }
            }
        } else {
            tokens.push(raw.to_string());
        }
    }

    let mut p = Parts::default();
    for tok in &tokens {
        if tok == "am" {
            p.ampm = Some(false);
            continue;
        }
        if tok == "pm" {
            p.ampm = Some(true);
            continue;
        }
        if tok == "gmt" || tok == "utc" || tok == "ut" {
            continue; // treated as UTC anyway
        }
        if let Some(m) = month_index(tok) {
            if p.mon.is_some() {
                return None;
            }
            p.mon = Some(m);
            continue;
        }
        if is_weekday(tok) {
            continue;
        }
        if tok.contains(':') {
            let (h, m, s) = parse_time(tok)?;
            if p.hour.is_some() {
                return None;
            }
            p.hour = Some(h);
            p.min = Some(m);
            p.sec = Some(s);
            continue;
        }
        if let Ok(v) = tok.parse::<i64>() {
            if v < 0 {
                return None;
            }
            // 4+ digits, or > 31, is unambiguously a year; otherwise day first.
            if tok.len() >= 4 || v > 31 {
                if p.year.is_some() {
                    return None;
                }
                p.year = Some(v);
            } else if p.day.is_none() {
                p.day = Some(v as u32);
            } else if p.year.is_none() {
                p.year = Some(v);
            } else {
                return None;
            }
            continue;
        }
        // Unrecognized token.
        return None;
    }

    let (day, mon, year) = (p.day?, p.mon?, p.year?);
    if day == 0 || day > 31 || mon == 0 || mon > 12 {
        return None;
    }
    let mut hour = p.hour.unwrap_or(0);
    let min = p.min.unwrap_or(0);
    let sec = p.sec.unwrap_or(0);
    match p.ampm {
        Some(true) if hour < 12 => hour += 12,
        Some(false) if hour == 12 => hour = 0,
        _ => {}
    }
    if hour > 23 {
        return None;
    }

    Some(caltime::timegm(year, mon, day, hour, min, sec))
}
