//! Terminator geometry: which columns of each rendered line are lit.
//!
//! The Moon disc is drawn as an ellipse (character cells are ~twice as tall as
//! wide, hence [`ASPECT_RATIO`] = 0.5). For a given line, the illuminated span
//! runs from `colleft` to `colright` inclusive; one edge is scaled by the
//! terminator cosine so the lit region sweeps across the disc with the phase.
//!
//! Integer truncation here deliberately mirrors C's `(int)` cast (toward zero),
//! which Rust's `f64 as i32` reproduces, so column boundaries land identically.

use std::f64::consts::PI;

/// Character cell aspect ratio. Changing this invalidates the canned art.
pub const ASPECT_RATIO: f64 = 0.5;

/// Number of character columns for a moon of `numlines` lines (`2 * numlines`).
pub fn numcols(numlines: i32) -> i32 {
    let yrad = numlines as f64 / 2.0;
    let xrad = yrad / ASPECT_RATIO;
    (xrad * 2.0) as i32
}

/// Inclusive `[colleft, colright]` lit span for one line at a given phase.
#[derive(Clone, Copy, Debug)]
pub struct Span {
    pub colleft: i32,
    pub colright: i32,
}

/// Compute the lit span for line `lin` of a `numlines`-tall moon whose
/// terminator fraction is `pctphase` (0 = new, 0.5 = full).
pub fn line_span(numlines: i32, lin: i32, pctphase: f64) -> Span {
    let yrad = numlines as f64 / 2.0;
    let xrad = yrad / ASPECT_RATIO;
    let angphase = pctphase * 2.0 * PI;
    let mcap = -angphase.cos();

    let y = lin as f64 + 0.5 - yrad;
    let mut xright = xrad * (1.0 - (y * y) / (yrad * yrad)).sqrt();
    let mut xleft = -xright;
    if (0.0..PI).contains(&angphase) {
        xleft = mcap * xleft;
    } else {
        xright = mcap * xright;
    }

    let base = (xrad + 0.5) as i32;
    Span {
        colleft: base + (xleft + 0.5) as i32,
        colright: base + (xright + 0.5) as i32,
    }
}
