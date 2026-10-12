#!/usr/bin/env python3
"""Enable rustix eventfd on macOS via Wawona L0 epoll-shim.

Smithay drm_syncobj uses rustix::event::eventfd. rustix gates that API on
linux/freebsd/illumos/espidf. Darwin has no syscall; Wawona already ships
jiixyj epoll-shim (same substrate as libwayland / fuzzel), which implements
eventfd(2) on kqueue with EFD_* == Darwin O_CLOEXEC / O_NONBLOCK.

This mutates the cargo-vendor rustix-1.* tree in place (niri macos.nix
preConfigure). Link -lepoll-shim or the FFI will fail at final ld.
"""
from __future__ import annotations

import sys
from pathlib import Path

EVENTFD_CFG = """    linux_kernel,
    target_os = "freebsd",
    target_os = "illumos",
    target_os = "espidf"
"""
EVENTFD_CFG_MACOS = """    linux_kernel,
    target_os = "freebsd",
    target_os = "illumos",
    target_os = "espidf",
    target_os = "macos"
"""

TYPES_CONSTANTS = """        /// `EFD_CLOEXEC`
        #[cfg(not(any(target_os = "espidf", target_os = "macos")))]
        const CLOEXEC = bitcast!(c::EFD_CLOEXEC);
        /// Darwin O_CLOEXEC; epoll-shim `#define EFD_CLOEXEC O_CLOEXEC`.
        #[cfg(target_os = "macos")]
        const CLOEXEC = 0x0100_0000;
        /// `EFD_NONBLOCK`
        #[cfg(not(any(target_os = "espidf", target_os = "macos")))]
        const NONBLOCK = bitcast!(c::EFD_NONBLOCK);
        /// Darwin O_NONBLOCK; epoll-shim `#define EFD_NONBLOCK O_NONBLOCK`.
        #[cfg(target_os = "macos")]
        const NONBLOCK = 0x0000_0004;
        /// `EFD_SEMAPHORE`
        #[cfg(not(any(target_os = "espidf", target_os = "macos")))]
        const SEMAPHORE = bitcast!(c::EFD_SEMAPHORE);
        #[cfg(target_os = "macos")]
        const SEMAPHORE = 1;
"""

SYSCALL_MACOS = """
    // Wawona: L0 epoll-shim eventfd(2) (kqueue). Same C ABI as Linux.
    #[cfg(target_os = "macos")]
    unsafe {
        extern "C" {
            fn eventfd(initval: c::c_uint, flags: c::c_int) -> c::c_int;
        }
        ret_owned_fd(eventfd(initval, bitflags_bits!(flags)))
    }
"""


def writable(path: Path) -> None:
    path.chmod(path.stat().st_mode | 0o200)


def must_replace(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"{label}: expected text not found")
    return text.replace(old, new, 1)


def patch_event_mod(path: Path) -> None:
    t = path.read_text()
    if "target_os = \"macos\"" in t and "mod eventfd" in t:
        print(f"already patched {path}")
        return
    t = t.replace(EVENTFD_CFG, EVENTFD_CFG_MACOS)
    if t.count('target_os = "macos"') < 2:
        raise SystemExit(f"{path}: macos cfg not applied to both eventfd sites")
    writable(path)
    path.write_text(t)
    print(f"patched {path}")


def patch_types(path: Path) -> None:
    t = path.read_text()
    if "Darwin O_CLOEXEC" in t:
        print(f"already patched {path}")
        return
    t = t.replace(EVENTFD_CFG, EVENTFD_CFG_MACOS)
    old = """        /// `EFD_CLOEXEC`
        #[cfg(not(target_os = "espidf"))]
        const CLOEXEC = bitcast!(c::EFD_CLOEXEC);
        /// `EFD_NONBLOCK`
        #[cfg(not(target_os = "espidf"))]
        const NONBLOCK = bitcast!(c::EFD_NONBLOCK);
        /// `EFD_SEMAPHORE`
        #[cfg(not(target_os = "espidf"))]
        const SEMAPHORE = bitcast!(c::EFD_SEMAPHORE);
"""
    t = must_replace(t, old, TYPES_CONSTANTS, str(path))
    writable(path)
    path.write_text(t)
    print(f"patched {path}")


def patch_syscalls(path: Path) -> None:
    t = path.read_text()
    if "L0 epoll-shim eventfd" in t:
        print(f"already patched {path}")
        return
    t = t.replace(EVENTFD_CFG, EVENTFD_CFG_MACOS)
    t = must_replace(
        t,
        """    #[cfg(any(target_os = "illumos", target_os = "espidf"))]
    unsafe {
        ret_owned_fd(c::eventfd(initval, bitflags_bits!(flags)))
    }
}
""",
        """    #[cfg(any(target_os = "illumos", target_os = "espidf"))]
    unsafe {
        ret_owned_fd(c::eventfd(initval, bitflags_bits!(flags)))
    }
"""
        + SYSCALL_MACOS
        + "}\n",
        str(path),
    )
    writable(path)
    path.write_text(t)
    print(f"patched {path}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: macos-rustix-eventfd-epoll-shim.py <cargo-vendor-dir>", file=sys.stderr)
        return 2
    vendor = Path(sys.argv[1])
    found = False
    for rustix in sorted(vendor.glob("rustix-1.*")):
        event_mod = rustix / "src" / "event" / "mod.rs"
        types = rustix / "src" / "backend" / "libc" / "event" / "types.rs"
        syscalls = rustix / "src" / "backend" / "libc" / "event" / "syscalls.rs"
        if not event_mod.is_file():
            continue
        found = True
        patch_event_mod(event_mod)
        if types.is_file():
            patch_types(types)
        if syscalls.is_file():
            patch_syscalls(syscalls)
    if not found:
        raise SystemExit(f"no rustix-1.* under {vendor}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
