fn main() {
    let lines = cli_kit::stdin_lines().unwrap_or_default();
    let mut prev: Option<String> = None;
    for line in lines {
        if prev.as_ref() != Some(&line) {
            cli_kit::writeln_stdout(&line);
            prev = Some(line);
        }
    }
}
