# Weston clients as debs (no App Store patches)

Optional software policy: `wawona-optional-software`.

Weston compositor and clients ship as **process debs** from
`repo.wawona.io/pkgs/wayland/`. Those recipes must **not** use:

- `compositor-apple-mobile.nix`
- `weston_simple_shm_main` / `weston_compositor_main` renames
- no-fork / no-exec / in-process cairo skips

Apple-mobile static archives in this repo are **legacy** while Wawona still
force-loads them. After Machines launches the installed deb, delete the matching
App Store patch set and patch-anchor CI for that client.

Keep App Store patches only on zsh, uutils, and fastfetch (other repos).
