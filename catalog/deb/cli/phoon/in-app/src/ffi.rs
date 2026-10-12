//! C ABI entry point for in-process linking on Apple mobile (mirrors the
//! `waypipe_main` / `fastfetch_main` model used elsewhere in Wawona). The
//! Wawona shell dispatcher declares `phoon_main` weak and forwards `argv` to it.

use std::ffi::CStr;
use std::os::raw::{c_char, c_int};

/// `int phoon_main(int argc, char **argv)`.
///
/// # Safety
/// `argv` must point to `argc` valid, NUL-terminated C strings (or be null),
/// exactly as a C `main` receives it.
#[no_mangle]
pub unsafe extern "C" fn phoon_main(argc: c_int, argv: *const *const c_char) -> c_int {
    let mut args: Vec<String> = Vec::new();
    if !argv.is_null() {
        for i in 0..argc.max(0) as isize {
            let p = *argv.offset(i);
            if p.is_null() {
                continue;
            }
            args.push(CStr::from_ptr(p).to_string_lossy().into_owned());
        }
    }
    if args.is_empty() {
        args.push("phoon".to_string());
    }
    // Never let a panic unwind across the C ABI boundary into the host process
    // (that is UB). Catch it and report a nonzero status instead.
    match std::panic::catch_unwind(|| crate::cli::run(&args)) {
        Ok(code) => code,
        Err(_) => 1,
    }
}
