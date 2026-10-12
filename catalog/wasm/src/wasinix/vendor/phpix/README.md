# vendor/phpix (placeholder)

Upstream `wasmerio/phpix` is no longer reachable (404), so the PHP lane cannot
fetch its submodule. This directory is intentionally a placeholder so the
`phpix` derivations still evaluate; they are excluded from `allWasm` /
`allWasmer` and are not built by CI.

The GTK / WASIX library lane added on this branch does not use PHP. If the
phpix source is recovered, restore the submodule and revert this placeholder.
