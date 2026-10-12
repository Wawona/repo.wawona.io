#!/usr/bin/env python3
"""Bridge smithay UdevBackend AsFd via RawFd (io_lifetimes / Android targets)."""
import os
import pathlib
import sys


def find_vendors():
    top = pathlib.Path(os.environ.get("NIX_BUILD_TOP", "."))
    found = set()
    for pattern in ("niri-android-*-vendor", "*-vendor"):
        for cand in top.glob(pattern):
            if cand.is_dir() and list(cand.glob("smithay-*/src/backend/udev.rs")):
                found.add(cand.resolve())
    if found:
        return sorted(found)
    here = pathlib.Path.cwd()
    for cand in here.parent.glob("*-vendor"):
        if cand.is_dir() and list(cand.glob("smithay-*")):
            found.add(cand.resolve())
    if not found:
        sys.exit(f"smithay vendor not found under {top} or {here.parent}")
    return sorted(found)


def main() -> None:
    for dst in find_vendors():
        for udev in dst.glob("smithay-*/src/backend/udev.rs"):
            text = udev.read_text()
            if (
                "borrow_raw(self.monitor.as_raw_fd())" in text
                or "AsRawFd::as_raw_fd(&self.monitor)" in text
            ):
                print("already patched", udev)
                continue
            old = """impl AsFd for UdevBackend {
    fn as_fd(&self) -> BorrowedFd<'_> {
        self.monitor.as_fd()
    }
}"""
            new = """impl AsFd for UdevBackend {
    fn as_fd(&self) -> BorrowedFd<'_> {
        unsafe { BorrowedFd::borrow_raw(std::os::fd::AsRawFd::as_raw_fd(&self.monitor)) }
    }
}"""
            if old not in text:
                print("skip (AsFd shape differs)", udev)
                continue
            udev.write_text(text.replace(old, new, 1))
            print("patched", udev)


if __name__ == "__main__":
    main()
