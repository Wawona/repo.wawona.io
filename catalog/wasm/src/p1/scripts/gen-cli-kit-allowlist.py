#!/usr/bin/env python3
"""Print [[packages]] TOML rows for cli-kit bins (helper for maintainers)."""
from __future__ import annotations

# name -> (smoke_args, smoke_stdin, smoke_expect, smoke_exit)
TOOLS = {
    "cat": (["--"], "hi\n", "hi", 0),  # -- ignored; use stdin only via empty args
    "head": (["-n", "1"], "a\nb\n", "a", 0),
    "tail": (["-n", "1"], "a\nb\n", "b", 0),
    "wc": (["-l"], "a\nb\n", "2", 0),
    "sort": ([], "b\na\n", "a", 0),
    "uniq": ([], "a\na\nb\n", "a", 0),
    "tr": (["a", "b"], "a\n", "b", 0),
    "cut": (["-d", ":", "-f", "2"], "x:y:z\n", "y", 0),
    "echo": (["hello"], "", "hello", 0),
    "yes": (["--once", "y"], "", "y", 0),
    "false": ([], "", "", 1),
    "tee": ([], "z\n", "z", 0),
    "basename": (["/a/b/c"], "", "c", 0),
    "dirname": (["/a/b/c"], "", "/a/b", 0),
    "pwd": ([], "", "/", 0),  # wasmtime often /; accept substring via expect
    "env": ([], "", "=", 0),
    "base64": ([], "hi", "aGk=", 0),
    "cksum": ([], "a", "97 1", 0),
    "seq": (["3"], "", "1", 0),
    "rev": ([], "ab\n", "ba", 0),
    "nl": ([], "x\n", "x", 0),
    "fold": (["-w", "2"], "abcd\n", "ab", 0),
}


def fmt_list(xs):
    if not xs:
        return "[]"
    # cat should not get "--"
    return "[" + ", ".join(f'"{x}"' for x in xs) + "]"


def main():
    # Fix cat: no args
    TOOLS["cat"] = ([], "hi\n", "hi", 0)
    for name, (args, stdin, expect, exit_code) in TOOLS.items():
        print("[[packages]]")
        print(f'name = "{name}"')
        print('version = "0.1.0"')
        print('abi = "wasi-p1"')
        print('status = "active"')
        print('build = "cargo-wasip1"')
        print('version_policy = "local"')
        print('source = "packages/cli-kit"')
        print(f'bin = "{name}"')
        print(f'summary = "Minimal WASI P1 {name} (cli-kit)"')
        print(f"smoke_args = {fmt_list(args)}")
        if stdin:
            # escape for toml
            esc = stdin.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            print(f'smoke_stdin = "{esc}"')
        else:
            print('smoke_stdin = ""')
        print(f'smoke_expect = "{expect}"')
        if exit_code != 0:
            print(f"smoke_exit = {exit_code}")
        print()


if __name__ == "__main__":
    main()
