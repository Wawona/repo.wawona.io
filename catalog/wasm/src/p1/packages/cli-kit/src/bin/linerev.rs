fn main() {
    for line in cli_kit::stdin_lines().unwrap_or_default() {
        let r: String = line.chars().rev().collect();
        cli_kit::writeln_stdout(&r);
    }
}
