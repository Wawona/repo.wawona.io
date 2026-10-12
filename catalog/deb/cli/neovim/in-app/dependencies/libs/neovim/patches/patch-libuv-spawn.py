#!/usr/bin/env python3
"""App Store–safe Neovim on Apple mobile: no uv_spawn / external processes."""
from pathlib import Path

path = Path("src/nvim/event/libuv_process.c")
text = path.read_text()
if "WAWONA_APPLE_MOBILE_SPAWN" in text:
    raise SystemExit(0)

include_anchor = '#include "nvim/ui_client.h"'
include_patch = include_anchor + """

#if defined(WAWONA_APPLE_MOBILE)
#define WAWONA_APPLE_MOBILE_SPAWN 1
#endif
"""
if include_anchor not in text:
    raise SystemExit("libuv_process.c ui_client include missing")
text = text.replace(include_anchor, include_patch, 1)

spawn_anchor = """  int status;
  if ((status = uv_spawn(&proc->loop->uv, &uvproc->uv, &uvproc->uvopts))) {
    ILOG("uv_spawn(%s) failed: %s", uvproc->uvopts.file, uv_strerror(status));"""
spawn_patch = """#if WAWONA_APPLE_MOBILE_SPAWN
  if (uvproc->uvopts.env) {
    os_free_fullenv(uvproc->uvopts.env);
  }
  return UV_ENOSYS;
#else
  int status;
  if ((status = uv_spawn(&proc->loop->uv, &uvproc->uv, &uvproc->uvopts))) {
    ILOG("uv_spawn(%s) failed: %s", uvproc->uvopts.file, uv_strerror(status));"""
if spawn_anchor not in text:
    raise SystemExit("libuv_process.c uv_spawn anchor missing")
text = text.replace(spawn_anchor, spawn_patch, 1)

return_anchor = """  proc->pid = uvproc->uv.pid;
  return status;
}"""
return_patch = """  proc->pid = uvproc->uv.pid;
  return status;
#endif
}"""
if return_anchor not in text:
    raise SystemExit("libuv_process.c return anchor missing")
text = text.replace(return_anchor, return_patch, 1)
path.write_text(text)
