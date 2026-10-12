//! Minimal WASI P1 CLI. Default prints hello; optional argv joins as a message.
fn main() {
    let mut args = std::env::args().skip(1);
    match args.next() {
        None => println!("hello"),
        Some(first) => {
            let mut msg = first;
            for a in args {
                msg.push(' ');
                msg.push_str(&a);
            }
            println!("{msg}");
        }
    }
}
