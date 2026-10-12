//! Minimal, dependency-free UTC calendar arithmetic.
//!
//! `phoon-rs` operates entirely in UTC so that its output is deterministic and
//! reproducible on every platform (Apple mobile, Android, Linux) without a
//! timezone database. The original `phoon` honoured `$TZ` via libc
//! `localtime`/`mktime`; run the reference with `TZ=UTC` to compare byte-for-byte.
//!
//! The civil<->days conversions are the well-known public-domain algorithms by
//! Howard Hinnant (`days_from_civil` / `civil_from_days`).

/// Broken-down UTC time.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Tm {
    pub year: i64,
    /// 1..=12
    pub mon: u32,
    /// 1..=31
    pub mday: u32,
    pub hour: u32,
    pub min: u32,
    pub sec: u32,
    /// 0 = Sunday
    pub wday: u32,
}

const SECS_PER_DAY: i64 = 86_400;

/// Days since 1970-01-01 for a proleptic-Gregorian civil date. Public domain
/// (Howard Hinnant). `m` is 1..=12, `d` is 1..=31.
pub fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = (y - era * 400) as i64; // [0, 399]
    let m = m as i64;
    let d = d as i64;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1; // [0, 365]
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy; // [0, 146096]
    era * 146_097 + doe - 719_468
}

/// Inverse of [`days_from_civil`]: returns `(year, month 1..=12, day 1..=31)`.
pub fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365; // [0, 399]
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let m = (if mp < 10 { mp + 3 } else { mp - 9 }) as u32; // [1, 12]
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// libc `gmtime` for a Unix timestamp (UTC).
pub fn gmtime(t: i64) -> Tm {
    let days = t.div_euclid(SECS_PER_DAY);
    let rem = t.rem_euclid(SECS_PER_DAY);
    let (year, mon, mday) = civil_from_days(days);
    // 1970-01-01 was a Thursday (wday = 4).
    let wday = (days.rem_euclid(7) + 4).rem_euclid(7) as u32;
    Tm {
        year,
        mon,
        mday,
        hour: (rem / 3600) as u32,
        min: ((rem % 3600) / 60) as u32,
        sec: (rem % 60) as u32,
        wday,
    }
}

/// libc `timegm`: broken-down UTC time -> Unix timestamp.
pub fn timegm(year: i64, mon: u32, mday: u32, hour: u32, min: u32, sec: u32) -> i64 {
    days_from_civil(year, mon, mday) * SECS_PER_DAY
        + hour as i64 * 3600
        + min as i64 * 60
        + sec as i64
}
