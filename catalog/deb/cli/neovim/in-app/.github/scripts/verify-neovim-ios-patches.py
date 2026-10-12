#!/usr/bin/env python3
"""Verify Neovim Apple-mobile compliance patches still apply to upstream anchors."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
PATCH_DIR = ROOT / "dependencies" / "libs" / "neovim" / "patches"
TOOLCHAIN_ROOT = Path(
    os.environ.get("WWN_TOOLCHAIN_ROOT", ROOT.parent / "wwn-toolchain")
)
ZSH_ROOT = Path(os.environ.get("WWN_ZSH_ROOT", ROOT.parent / "wwn-zsh"))
DISPATCH_C = TOOLCHAIN_ROOT / "dependencies/libs/wawona-pty/src/wawona-dispatch.c"
ROOTFS_NIX = ZSH_ROOT / "dependencies/wawona/ios-rootfs.nix"
URL = "https://github.com/neovim/neovim/archive/refs/tags/v0.10.4.tar.gz"
VERSION = "0.10.4"

BANNED_IN_MOBILE = ("fork(", "execve(", "posix_spawn", "posix_spawnp", "system(", "dlopen(", "MAP_JIT")

CODEGEN_MARKERS = (
    "WAWONA_HOST_NLUA0",
    "WAWONA_GEN_CC",
    "WAWONA_MACOS_SDK",
    "unset(HAVE_BE64TOH)",
)

PATCH_PY_MARKERS = (
    "WAWONA_APPLE_MOBILE",
    "patch-libuv-spawn.py",
    "cmake-apple-mobile-flags.snippet",
    "USE_LUAJIT OFF",
    "ENABLE_LTO OFF",
    *CODEGEN_MARKERS,
)


def apply_patches(src: Path) -> None:
    for name in ("patch-neovim-apple-mobile.py", "patch-libuv-spawn.py"):
        subprocess.check_call(["python3", str(PATCH_DIR / name)], cwd=src)
    snippet = PATCH_DIR / "cmake-apple-mobile-flags.snippet"
    if "WAWONA_APPLE_MOBILE" not in (src / "CMakeLists.txt").read_text():
        raise SystemExit("cmake snippet not applied")


def _inproc_clients(rootfs: str) -> set[str]:
    m = re.search(r"WAWONA_INPROC_CLIENTS=\((.*?)\)", rootfs, re.DOTALL)
    if not m:
        raise SystemExit("ios-rootfs.nix: cannot find WAWONA_INPROC_CLIENTS list")
    return set(re.findall(r"\b([a-z][a-z0-9-]+)\b", m.group(1)))


def _dispatch_nvim_names(dispatch: str) -> set[str]:
    names = set(re.findall(r'strcmp\(name,\s*"([^"]+)"\)', dispatch))
    return {n for n in names if n in {"nvim", "vi", "vim"}}


def check_inproc_tool_sync() -> None:
    if not DISPATCH_C.is_file():
        print(f"FAIL dispatch sync ({DISPATCH_C} missing)", file=sys.stderr)
        sys.exit(1)
    if not ROOTFS_NIX.is_file():
        print(f"FAIL dispatch sync ({ROOTFS_NIX} missing)", file=sys.stderr)
        sys.exit(1)
    rootfs_set = _inproc_clients(ROOTFS_NIX.read_text())
    dispatch_set = _dispatch_nvim_names(DISPATCH_C.read_text())
    expected = {"nvim", "vi", "vim"}
    if dispatch_set != expected:
        print(f"FAIL dispatch nvim names expected {expected}, got {dispatch_set}",
              file=sys.stderr)
        sys.exit(1)
    missing = expected - rootfs_set
    if missing:
        print(f"FAIL WAWONA_INPROC_CLIENTS missing nvim aliases: {sorted(missing)}",
              file=sys.stderr)
        sys.exit(1)
    print("OK nvim/vi/vim in WAWONA_INPROC_CLIENTS ↔ wawona-dispatch.c")


def main() -> int:
    patch_py = (PATCH_DIR / "patch-neovim-apple-mobile.py").read_text()
    snippet = (PATCH_DIR / "cmake-apple-mobile-flags.snippet").read_text()
    for marker in PATCH_PY_MARKERS:
        hay = patch_py if marker in CODEGEN_MARKERS or marker.startswith("WAWONA") else snippet
        if marker not in hay and marker not in patch_py and marker not in snippet:
            print(f"missing marker in patches: {marker}", file=sys.stderr)
            return 1

    with tempfile.TemporaryDirectory() as tmp:
        tgz = Path(tmp) / "src.tar.gz"
        urllib.request.urlretrieve(URL, tgz)
        subprocess.check_call(["tar", "-xzf", str(tgz), "-C", tmp])
        src = Path(tmp) / f"neovim-{VERSION}"
        apply_patches(src)
        libuv = (src / "src/nvim/event/libuv_process.c").read_text()
        if "WAWONA_APPLE_MOBILE_SPAWN" not in libuv:
            print("missing spawn guard in libuv_process.c", file=sys.stderr)
            return 1
        shell = (src / "src/nvim/os/shell.c").read_text()
        if "App Store compliance" not in shell:
            print("missing shell stub", file=sys.stderr)
            return 1
        lang = (src / "src/nvim/os/lang.c").read_text()
        if "CFLocaleCopyCurrent" not in lang:
            print("missing Apple-mobile lang_init CFLocale path", file=sys.stderr)
            return 1
        nvim_cmake = (src / "src/nvim/CMakeLists.txt").read_text()
        for marker in CODEGEN_MARKERS[:3]:
            if marker not in nvim_cmake:
                print(f"missing codegen anchor in src/nvim/CMakeLists.txt: {marker}",
                      file=sys.stderr)
                return 1
        config_cmake = (src / "cmake.config/CMakeLists.txt").read_text()
        if "unset(HAVE_BE64TOH)" not in config_cmake:
            print("missing HAVE_BE64TOH unset for Apple mobile", file=sys.stderr)
            return 1
        cmake = (src / "CMakeLists.txt").read_text()
        if "WAWONA_APPLE_MOBILE" not in cmake:
            print("missing cmake option", file=sys.stderr)
            return 1
        if "ENABLE_LTO OFF" not in snippet:
            print("missing ENABLE_LTO OFF in cmake snippet", file=sys.stderr)
            return 1
        deps_cmake = (src / "cmake.deps/CMakeLists.txt").read_text()
        if "set(USE_BUNDLED_LUA ON" not in deps_cmake:
            print("missing PUC Lua in cmake.deps", file=sys.stderr)
            return 1
        for token in BANNED_IN_MOBILE:
            if token in libuv.split("#else")[0]:
                print(f"unexpected {token} before #else in libuv_process.c", file=sys.stderr)
                return 1

    check_inproc_tool_sync()
    print("neovim patch anchors OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
