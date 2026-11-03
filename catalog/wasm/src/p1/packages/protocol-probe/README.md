# protocol-probe

WASI P1 Wayland guest that checks compositor advertisement honesty against
per-profile expect JSON generated from Wawona's `PROTOCOL_CATALOG`.

## Modes

| Args | Behavior |
|------|----------|
| (default) | Connect `WAYLAND_DISPLAY`, dump registry, diff expect, shallow smokes |
| `--self-check` | Validate embedded expect JSON only (Wasmtime catalog smoke) |
| `--human` | Also print a one-line summary on stderr |

Profile: `WAWONA_PROTOCOL_PROFILE` (`store-safe` default, `store-safe-remote`,
`desktop-host`, `full-dev`).

Stdout is NDJSON. Exit codes: `0` ok, `1` missing required, `2` unexpected,
`3` smoke fail, `4` connect/ABI/expect parse.

## Regenerate expects

From the Wawona repo:

```bash
./scripts/gen-protocol-expect.sh
```

That writes `docs/protocol-expect/*.json` and copies them into
`packages/protocol-probe/expect/`.

## Non-goals

Does not deep-test all 168 Functional handlers. Semantic conformance stays
on WLCS, `protocol_matrix`, and Kani proofs.
