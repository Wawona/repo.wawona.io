//! `phoon` — show the phase of the moon (clean-room Rust, output-compatible).

fn main() {
    std::process::exit(phoon_rs::cli::run_from_env());
}
