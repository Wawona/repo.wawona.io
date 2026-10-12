//! Unit tests for the calendar, date parser, and lunar model.

use phoon_rs::{caltime, dateparse, Moon};

#[test]
fn caltime_roundtrips_epoch() {
    for &t in &[0i64, 947_160_000, 1_786_190_400, -86_400, 949_406_400] {
        let tm = caltime::gmtime(t);
        let back = caltime::timegm(tm.year, tm.mon, tm.mday, tm.hour, tm.min, tm.sec);
        assert_eq!(back, t, "roundtrip failed for {t}");
    }
    // 2000-01-01 00:00:00 UTC.
    let tm = caltime::gmtime(946_684_800);
    assert_eq!((tm.year, tm.mon, tm.mday), (2000, 1, 1));
    assert_eq!(tm.wday, 6); // Saturday
}

#[test]
fn dateparse_accepts_supported_forms() {
    let want = caltime::timegm(2000, 1, 6, 12, 0, 0);
    for s in [
        "6 Jan 2000 12:00:00",
        "6 jan 2000 12:00:00",
        "6-jan-2000 12:00:00",
        "Jan 6 12:00:00 2000",
        "12:00:00 6 Jan 2000",
        "Thu Jan 6 12:00:00 2000",
    ] {
        assert_eq!(dateparse::parse(s), Some(want), "parsing `{s}`");
    }
    // Date-only defaults to midnight.
    assert_eq!(
        dateparse::parse("6 Jan 2000"),
        Some(caltime::timegm(2000, 1, 6, 0, 0, 0))
    );
}

#[test]
fn dateparse_rejects_unsupported_forms() {
    for s in ["2000-01-06", "01/06/2000", "not a date", "Jan 2000", ""] {
        assert_eq!(dateparse::parse(s), None, "should reject `{s}`");
    }
}

#[test]
fn illumination_tracks_phase() {
    // New moon ~ 2000-01-06, full ~ 2000-01-21.
    let new = Moon::at(947_160_000).illuminated_fraction();
    let full = Moon::at(948_456_000).illuminated_fraction();
    assert!(new < 0.05, "new-moon illumination {new} too high");
    assert!(full > 0.95, "full-moon illumination {full} too low");
    // Phase fraction is within [0, 1).
    let p = Moon::at(948_456_000).phase_fraction();
    assert!((0.0..1.0).contains(&p));
}

#[test]
fn render_is_deterministic_with_fixed_clock() {
    let m = Moon::at(947_937_600);
    let a = m.render_with_clock(23, 1_000_000_000);
    let b = m.render_with_clock(23, 1_000_000_000);
    assert_eq!(a, b);
    assert!(a.ends_with(b"\n"));
}
