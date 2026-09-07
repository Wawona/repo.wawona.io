# Agent notes

## Product boundaries

Dual channel `/wasm/v1` vs APT / `/jailbreak`. Humans pick a catalog at `/search/`
(Mode A wasm or Mode B debs, never one mixed list). `/jailbreak/` is a human
landing onto the deb catalog. APT stays at `https://repo.wawona.io/`.
See `.cursor/rules/repo-wawona-io-channels.mdc`.

Every wasm package and every `.deb` needs GitHub-queryable maintainers.
See `.cursor/rules/repo-wawona-io-maintainers.mdc` and
`python3 scripts/check-packages.py` (add `--offline` for flake checks).

Canonical Wawona docs: https://github.com/Wawona/Wawona/blob/development/docs/mode-a-b.md

