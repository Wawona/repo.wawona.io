fn main() {
    let s = cli_kit::stdin_to_string().unwrap_or_default();
    let sum: u32 = s.bytes().fold(0u32, |a, b| a.wrapping_add(b as u32));
    cli_kit::writeln_stdout(&format!("{sum} {}", s.len()));
}
