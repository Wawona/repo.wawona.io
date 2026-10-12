#!/usr/bin/env python3
"""Stub Lua os.execute on Apple mobile (system() unavailable on iOS SDK)."""
import sys
from pathlib import Path

loslib = Path(sys.argv[1])
text = loslib.read_text()
old = "  lua_pushinteger(L, system(luaL_optstring(L, 1, NULL)));"
new = "  lua_pushinteger(L, -1); (void)luaL_optstring(L, 1, NULL); /* WAWONA_APPLE_MOBILE */"
if old in text and "WAWONA_APPLE_MOBILE" not in text:
    loslib.write_text(text.replace(old, new, 1))
