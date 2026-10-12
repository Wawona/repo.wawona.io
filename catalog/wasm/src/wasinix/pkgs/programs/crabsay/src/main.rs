//! Minimal crabsay: print argv joined (demo WASIX CLI for Wasmer smokes).
//! Upstream github.com/nevzheng/crabsay is gone; this keeps the package name
//! and smoke contract (`args = ["hi"]` → expect `"hi"`).
fn main() {
    let mut args = std::env::args().skip(1);
    if let Some(first) = args.next() {
        print!("{first}");
        for a in args {
            print!(" {a}");
        }
        println!();
    }
}
