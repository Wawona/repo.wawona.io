//! Lunar model: Sun/Moon positions, phase, illumination, and phase-time hunting.
//!
//! These are the standard low-precision solar/lunar algorithms from
//! Duffett-Smith, *Practical Astronomy With Your Calculator* (CUP, 1981) and
//! Meeus, *Astronomical Formulae for Calculators* — the same public reference
//! material used by John Walker's `moontool` (fourmilab.ch/moontool), which is
//! in turn the historical basis for `phoon`'s phase computation. This module is
//! an independent implementation from those published equations, not a
//! translation of any particular program's source.

use std::f64::consts::PI;

// Reference epoch: 1980 January 0.0.
const EPOCH: f64 = 2_444_238.5;

// Sun's apparent orbit.
const ELONGE: f64 = 278.833540; // ecliptic longitude at epoch 1980.0
const ELONGP: f64 = 282.596403; // ecliptic longitude at perigee
const ECCENT: f64 = 0.016718; // eccentricity of Earth's orbit
const SUNSMAX: f64 = 1.495985e8; // semi-major axis of Earth's orbit, km
const SUNANGSIZ: f64 = 0.533128; // Sun's angular size at semi-major distance, deg

// Moon's orbit, epoch 1980.0.
const MMLONG: f64 = 64.975464; // mean longitude at epoch
const MMLONGP: f64 = 349.383063; // mean longitude of perigee at epoch
// (node longitude / inclination only affect ecliptic lat/long, which do not
// enter the phase or illumination used for rendering, so they are omitted.)
const MECC: f64 = 0.054900; // eccentricity of Moon's orbit
const MANGSIZ: f64 = 0.5181; // angular size at distance a
const MSMAX: f64 = 384_401.0; // semi-major axis of Moon's orbit, km
const MPARALLAX: f64 = 0.9507; // parallax at distance a
const SYNMONTH: f64 = 29.530_588_68; // synodic month, days

/// Seconds per day, as used when converting Julian-day deltas to a duration.
pub const SECS_PER_DAY: f64 = 86_400.0;

#[inline]
fn fixangle(a: f64) -> f64 {
    a - 360.0 * (a / 360.0).floor()
}
#[inline]
fn torad(d: f64) -> f64 {
    d * (PI / 180.0)
}
#[inline]
fn todeg(r: f64) -> f64 {
    r * (180.0 / PI)
}
#[inline]
fn dsin(d: f64) -> f64 {
    torad(d).sin()
}
#[inline]
fn dcos(d: f64) -> f64 {
    torad(d).cos()
}

/// Convert a Unix timestamp to an astronomical Julian date (day + fraction).
///
/// The tiny fractional offset matches the constant `phoon`/`moontool` use so
/// that boundary truncations in the rendered caption agree exactly.
pub fn unix_to_julian(t: i64) -> f64 {
    t as f64 / 86_400.0 + 2_440_587.499_999_666_666_666_6
}

/// Result of a full phase computation for a given instant.
#[derive(Clone, Copy, Debug)]
pub struct PhaseInfo {
    /// Terminator phase as a fraction of a full cycle, 0..1 (0 = new, 0.5 = full).
    pub pctphase: f64,
    /// Illuminated fraction of the disc, 0..1.
    pub illum: f64,
    /// Age of the Moon in days.
    pub age: f64,
    /// Distance from Earth centre, km.
    pub dist: f64,
    /// Angular diameter, degrees.
    pub angdia: f64,
    /// Distance to the Sun, km.
    pub sundist: f64,
    /// Sun's angular diameter, degrees.
    pub sunang: f64,
}

fn kepler(m_deg: f64, ecc: f64) -> f64 {
    const EPSILON: f64 = 1e-6;
    let m = torad(m_deg);
    let mut e = m;
    loop {
        let delta = e - ecc * e.sin() - m;
        e -= delta / (1.0 - ecc * e.cos());
        if delta.abs() <= EPSILON {
            break;
        }
    }
    e
}

/// Calculate the phase of the Moon for a Julian date.
pub fn phase(pdate: f64) -> PhaseInfo {
    // Sun's position.
    let day = pdate - EPOCH;
    let n = fixangle((360.0 / 365.2422) * day);
    let m = fixangle(n + ELONGE - ELONGP);
    let mut ec = kepler(m, ECCENT);
    ec = ((1.0 + ECCENT) / (1.0 - ECCENT)).sqrt() * (ec / 2.0).tan();
    ec = 2.0 * todeg(ec.atan()); // true anomaly
    let lambdasun = fixangle(ec + ELONGP);
    let f = (1.0 + ECCENT * torad(ec).cos()) / (1.0 - ECCENT * ECCENT);
    let sun_dist = SUNSMAX / f;
    let sun_ang = f * SUNANGSIZ;

    // Moon's position.
    let ml = fixangle(13.176_396_6 * day + MMLONG); // mean longitude
    let mm = fixangle(ml - 0.111_404_1 * day - MMLONGP); // mean anomaly
    let ev = 1.2739 * torad(2.0 * (ml - lambdasun) - mm).sin(); // evection
    let ae = 0.1858 * torad(m).sin(); // annual equation
    let a3 = 0.37 * torad(m).sin();
    let mm_p = mm + ev - ae - a3; // corrected anomaly
    let m_ec = 6.2886 * torad(mm_p).sin(); // equation of the centre
    let a4 = 0.214 * torad(2.0 * mm_p).sin();
    let l_p = ml + ev + m_ec - ae + a4; // corrected longitude
    let v = 0.6583 * torad(2.0 * (l_p - lambdasun)).sin(); // variation
    let l_pp = l_p + v; // true longitude

    // Phase.
    let moon_age = l_pp - lambdasun;
    let moon_phase = (1.0 - torad(moon_age).cos()) / 2.0;

    // Distance / angular size.
    let moon_dist = (MSMAX * (1.0 - MECC * MECC)) / (1.0 + MECC * torad(mm_p + m_ec).cos());
    let moon_dfrac = moon_dist / MSMAX;
    let moon_ang = MANGSIZ / moon_dfrac;
    let _moon_par = MPARALLAX / moon_dfrac;

    PhaseInfo {
        pctphase: fixangle(moon_age) / 360.0,
        illum: moon_phase,
        age: SYNMONTH * (fixangle(moon_age) / 360.0),
        dist: moon_dist,
        angdia: moon_ang,
        sundist: sun_dist,
        sunang: sun_ang,
    }
}

/// Which principal phase a hunted time corresponds to.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Principal {
    New = 0,
    First = 1,
    Full = 2,
    Last = 3,
}

impl Principal {
    fn from_selector(sel: f64) -> Self {
        match (sel * 4.0 + 0.001) as i32 {
            0 => Principal::New,
            1 => Principal::First,
            2 => Principal::Full,
            _ => Principal::Last,
        }
    }
}

fn jyear(td: f64) -> (i64, i64, i64) {
    let td = td + 0.5; // astronomical to civil
    let mut j = td.floor();
    j -= 1_721_119.0;
    let y0 = ((4.0 * j - 1.0) / 146_097.0).floor();
    j = j * 4.0 - (1.0 + 146_097.0 * y0);
    let mut d = (j / 4.0).floor();
    let j2 = ((4.0 * d + 3.0) / 1461.0).floor();
    d = (4.0 * d + 3.0) - 1461.0 * j2;
    d = ((d + 4.0) / 4.0).floor();
    let mut m = ((5.0 * d - 3.0) / 153.0).floor();
    d = (5.0 * d) - (3.0 + 153.0 * m);
    d = ((d + 5.0) / 5.0).floor();
    let mut y = 100.0 * y0 + j2;
    if m < 10.0 {
        m += 3.0;
    } else {
        m -= 9.0;
        y += 1.0;
    }
    (y as i64, m as i64, d as i64)
}

fn meanphase(sdate: f64, k: f64) -> f64 {
    let t = (sdate - 2_415_020.0) / 36525.0;
    let t2 = t * t;
    let t3 = t2 * t;
    2_415_020.759_33 + SYNMONTH * k + 0.000_117_8 * t2 - 0.000_000_155 * t3
        + 0.000_33 * dsin(166.56 + 132.87 * t - 0.009_173 * t2)
}

fn truephase(k: f64, pha: f64) -> f64 {
    let k = k + pha;
    let t = k / 1236.85;
    let t2 = t * t;
    let t3 = t2 * t;
    let mut pt = 2_415_020.759_33 + SYNMONTH * k + 0.000_117_8 * t2 - 0.000_000_155 * t3
        + 0.000_33 * dsin(166.56 + 132.87 * t - 0.009_173 * t2);
    let m = 359.2242 + 29.105_356_08 * k - 0.000_033_3 * t2 - 0.000_003_47 * t3;
    let mprime = 306.0253 + 385.816_918_06 * k + 0.010_730_6 * t2 + 0.000_012_36 * t3;
    let f = 21.2964 + 390.670_506_46 * k - 0.001_652_8 * t2 - 0.000_002_39 * t3;

    if pha < 0.01 || (pha - 0.5).abs() < 0.01 {
        // New and Full Moon corrections.
        pt += (0.1734 - 0.000_393 * t) * dsin(m) + 0.0021 * dsin(2.0 * m) - 0.4068 * dsin(mprime)
            + 0.0161 * dsin(2.0 * mprime)
            - 0.0004 * dsin(3.0 * mprime)
            + 0.0104 * dsin(2.0 * f)
            - 0.0051 * dsin(m + mprime)
            - 0.0074 * dsin(m - mprime)
            + 0.0004 * dsin(2.0 * f + m)
            - 0.0004 * dsin(2.0 * f - m)
            - 0.0006 * dsin(2.0 * f + mprime)
            + 0.0010 * dsin(2.0 * f - mprime)
            + 0.0005 * dsin(m + 2.0 * mprime);
    } else if (pha - 0.25).abs() < 0.01 || (pha - 0.75).abs() < 0.01 {
        pt += (0.1721 - 0.0004 * t) * dsin(m) + 0.0021 * dsin(2.0 * m) - 0.6280 * dsin(mprime)
            + 0.0089 * dsin(2.0 * mprime)
            - 0.0004 * dsin(3.0 * mprime)
            + 0.0079 * dsin(2.0 * f)
            - 0.0119 * dsin(m + mprime)
            - 0.0047 * dsin(m - mprime)
            + 0.0003 * dsin(2.0 * f + m)
            - 0.0004 * dsin(2.0 * f - m)
            - 0.0006 * dsin(2.0 * f + mprime)
            + 0.0021 * dsin(2.0 * f - mprime)
            + 0.0003 * dsin(m + 2.0 * mprime)
            + 0.0004 * dsin(m - 2.0 * mprime)
            - 0.0003 * dsin(2.0 * m + mprime);
        if pha < 0.5 {
            pt += 0.0028 - 0.0004 * dcos(m) + 0.0003 * dcos(mprime);
        } else {
            pt += -0.0028 + 0.0004 * dcos(m) - 0.0003 * dcos(mprime);
        }
    }
    pt
}

/// The five phase times bounding the lunation containing `sdate`
/// (new, first, full, last, next new).
pub fn phasehunt5(sdate: f64) -> [f64; 5] {
    let mut adate = sdate - 45.0;
    let (yy, mm, _dd) = jyear(adate);
    let mut k1 = ((yy as f64 + (mm as f64 - 1.0) * (1.0 / 12.0) - 1900.0) * 12.3685).floor();

    let mut nt1 = meanphase(adate, k1);
    adate = nt1;
    let k2;
    loop {
        adate += SYNMONTH;
        let kk2 = k1 + 1.0;
        let nt2 = meanphase(adate, kk2);
        if nt1 <= sdate && nt2 > sdate {
            k2 = kk2;
            break;
        }
        nt1 = nt2;
        k1 = kk2;
    }
    [
        truephase(k1, 0.0),
        truephase(k1, 0.25),
        truephase(k1, 0.5),
        truephase(k1, 0.75),
        truephase(k2, 0.0),
    ]
}

/// The principal phase just at/before `sdate` and the next one after it.
pub fn phasehunt2(sdate: f64) -> ([f64; 2], [Principal; 2]) {
    let p5 = phasehunt5(sdate);
    let mut phases = [p5[0], p5[1]];
    let mut which = [Principal::New, Principal::First];
    if phases[1] <= sdate {
        phases[0] = phases[1];
        which[0] = which[1];
        phases[1] = p5[2];
        which[1] = Principal::Full;
        if phases[1] <= sdate {
            phases[0] = phases[1];
            which[0] = which[1];
            phases[1] = p5[3];
            which[1] = Principal::Last;
            if phases[1] <= sdate {
                phases[0] = phases[1];
                which[0] = which[1];
                phases[1] = p5[4];
                which[1] = Principal::New;
            }
        }
    }
    (phases, which)
}

// Retained for API completeness / potential callers that pass raw selectors.
#[allow(dead_code)]
pub(crate) fn principal_from_selector(sel: f64) -> Principal {
    Principal::from_selector(sel)
}
