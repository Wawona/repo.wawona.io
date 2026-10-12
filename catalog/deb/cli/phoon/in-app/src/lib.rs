//! `phoon-rs` — an independent, dependency-free Rust implementation that
//! reproduces the terminal output of the historical `phoon` moon-phase utility
//! by Jef Poskanzer.
//!
//! This crate is a clean-room work: the astronomy is implemented from published
//! references (Duffett-Smith / Meeus, as used by John Walker's `moontool`) and
//! the renderer is derived from `phoon`'s *observable output*. It contains no
//! copied or translated `phoon` source.
//!
//! `phoon-rs` operates in UTC for deterministic, portable output. To compare
//! against the reference program byte-for-byte, run it with `TZ=UTC`.
//!
//! # Library use
//!
//! ```
//! use phoon_rs::Moon;
//! // Full moon-ish instant; render at 23 lines (the default size).
//! let moon = Moon::at(946_512_000);
//! let art = moon.render(23);
//! assert!(art.contains('\n'));
//! ```

pub mod caltime;
pub mod cli;
pub mod dateparse;
pub mod ffi;
pub mod geometry;
pub mod lunar;
pub mod render;

pub use lunar::{PhaseInfo, Principal};

/// Current Unix time in seconds (UTC), or 0 if the clock is before the epoch.
pub fn now_unix() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// A snapshot of the Moon at a specific instant, plus rendering.
#[derive(Clone, Copy, Debug)]
pub struct Moon {
    /// Unix timestamp (seconds, UTC) this snapshot represents.
    pub time: i64,
    info: PhaseInfo,
}

impl Moon {
    /// Compute the Moon's state at a Unix timestamp (seconds, UTC).
    pub fn at(unix_secs: i64) -> Self {
        Moon {
            time: unix_secs,
            info: lunar::phase(lunar::unix_to_julian(unix_secs)),
        }
    }

    /// The Moon right now.
    pub fn now() -> Self {
        Moon::at(now_unix())
    }

    /// Illuminated fraction of the disc, 0..1.
    pub fn illuminated_fraction(&self) -> f64 {
        self.info.illum
    }

    /// Terminator phase as a fraction of a cycle, 0..1 (0 = new, 0.5 = full).
    pub fn phase_fraction(&self) -> f64 {
        self.info.pctphase
    }

    /// Age of the Moon in days since the new moon.
    pub fn age_days(&self) -> f64 {
        self.info.age
    }

    /// Distance from the Earth's centre in kilometres.
    pub fn distance_km(&self) -> f64 {
        self.info.dist
    }

    /// Full phase computation (illumination, age, distance, angular sizes).
    pub fn info(&self) -> PhaseInfo {
        self.info
    }

    /// Render the ASCII moon at `lines` lines, using the current wall clock for
    /// the pseudo-random easter eggs (matching `phoon`'s default behavior).
    pub fn render(&self, lines: i32) -> String {
        self.render_string(lines, now_unix())
    }

    /// Render deterministically: `clock` drives the easter-egg selection instead
    /// of the wall clock. Pass a value with `clock % 13 != 3`, `clock % 23 != 3`
    /// for the plain (non-Hubert) frames.
    pub fn render_with_clock(&self, lines: i32, clock: i64) -> Vec<u8> {
        render::render_bytes(self.time, lines, clock)
    }

    fn render_string(&self, lines: i32, clock: i64) -> String {
        let bytes = render::render_bytes(self.time, lines, clock);
        match String::from_utf8(bytes) {
            Ok(s) => s,
            Err(e) => String::from_utf8_lossy(e.as_bytes()).into_owned(),
        }
    }
}
