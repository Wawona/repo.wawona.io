//! WASI P1 wrapper: EffectCraft expression syntax check (upstream crate).
//! Not the full EffectCraft GUI or effectcraft-cli.

fn main() {
    let mut args = std::env::args().skip(1);
    let expr = match args.next() {
        Some(s) => s,
        None => {
            eprintln!("usage: effectcraft-expr <expression>");
            std::process::exit(2);
        }
    };
    match effectcraft_expr::check_syntax(&expr) {
        Ok(()) => {
            println!("ok");
        }
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(1);
        }
    }
}
