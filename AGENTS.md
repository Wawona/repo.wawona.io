# Agent notes

## Learn loop (always)

Before coding, read `.cursor/skills/repo-wawona-io-priors/SKILL.md` and the
matching skill. Rule: `.cursor/rules/repo-wawona-io-agent-learn.mdc`.

New incident or "never do X": write it into a skill in the **same** change
(skill `repo-wawona-io-learn`). Do not leave the learning only in chat.

## Product boundaries

Dual channel `/wasm/v1` vs APT at repo root. Humans pick a catalog at `/search/`
(wasm for App Store / Play, or APT debs). Debs have two audiences: **Sileo** on
jailbroken iOS (rootless and rootful), and **Termux** on sideloaded Android
(not jailbreak, not Play). `/jailbreak/` is the Sileo bookmark. `/termux/` is
the Termux bookmark. APT stays at `https://repo.wawona.io/`.
See `.cursor/rules/repo-wawona-io-channels.mdc` and skill
`repo-wawona-io-catalogs`.

Every wasm package and every `.deb` needs GitHub-queryable maintainers.
See `.cursor/rules/repo-wawona-io-maintainers.mdc` and
`python3 scripts/check-packages.py` (add `--offline` for flake checks).

Canonical Wawona docs: https://github.com/Wawona/Wawona/blob/development/docs/mode-a-b.md
