#!/usr/bin/env python3
"""smithay-client-toolkit: use memfd on Android; never rustix::shm (Bionic)."""
import os
import pathlib
import sys


def find_raw() -> pathlib.Path:
    top = pathlib.Path(os.environ.get("NIX_BUILD_TOP", "."))
    for pattern in ("niri-android-*-vendor", "*-vendor"):
        for cand in top.glob(pattern):
            hits = list(cand.glob("smithay-client-toolkit-*/src/shm/raw.rs"))
            if hits:
                return hits[0]
    here = pathlib.Path.cwd()
    for cand in here.parent.glob("*-vendor"):
        hits = list(cand.glob("smithay-client-toolkit-*/src/shm/raw.rs"))
        if hits:
            return hits[0]
    sys.exit("sctk shm/raw.rs not found")


def main() -> None:
    p = find_raw()
    text = p.read_text()
    if 'any(target_os = "linux", target_os = "android")' in text and "rustix::shm::shm_open" not in text:
        print("already patched", p)
        return

    old_import = """use rustix::{
    io::Errno,
    shm::{Mode, ShmOFlags},
};"""
    new_import = """use rustix::io::Errno;
#[cfg(not(target_os = "android"))]
use rustix::shm::{Mode, ShmOFlags};"""
    if old_import not in text:
        sys.exit(f"sctk import block not found in {p}")
    text = text.replace(old_import, new_import, 1)

    text = text.replace(
        '#[cfg(target_os = "linux")]\n        {\n            match RawPool::create_memfd()',
        '#[cfg(any(target_os = "linux", target_os = "android"))]\n        {\n            match RawPool::create_memfd()',
        1,
    )
    text = text.replace(
        '    #[cfg(target_os = "linux")]\n    fn create_memfd()',
        '    #[cfg(any(target_os = "linux", target_os = "android"))]\n    fn create_memfd()',
        1,
    )

    old_fallback = """        let time = SystemTime::now();
        let mut mem_file_handle = format!(
            "/smithay-client-toolkit-{}",
            time.duration_since(UNIX_EPOCH).unwrap().subsec_nanos()
        );

        loop {
            let flags = ShmOFlags::CREATE | ShmOFlags::EXCL | ShmOFlags::RDWR;

            let mode = Mode::RUSR | Mode::WUSR;

            match rustix::shm::shm_open(mem_file_handle.as_str(), flags, mode) {
                Ok(fd) => match rustix::shm::shm_unlink(mem_file_handle.as_str()) {
                    Ok(_) => return Ok(fd),

                    Err(errno) => {
                        return Err(errno.into());
                    }
                },

                Err(Errno::EXIST) => {
                    // Change the handle if we happen to be duplicate.
                    let time = SystemTime::now();

                    mem_file_handle = format!(
                        "/smithay-client-toolkit-{}",
                        time.duration_since(UNIX_EPOCH).unwrap().subsec_nanos()
                    );

                    continue;
                }

                Err(Errno::INTR) => continue,

                Err(err) => return Err(err.into()),
            }
        }
    }"""
    new_fallback = """        #[cfg(not(target_os = "android"))]
        {
            let time = SystemTime::now();
            let mut mem_file_handle = format!(
                "/smithay-client-toolkit-{}",
                time.duration_since(UNIX_EPOCH).unwrap().subsec_nanos()
            );

            loop {
                let flags = ShmOFlags::CREATE | ShmOFlags::EXCL | ShmOFlags::RDWR;

                let mode = Mode::RUSR | Mode::WUSR;

                match rustix::shm::shm_open(mem_file_handle.as_str(), flags, mode) {
                    Ok(fd) => match rustix::shm::shm_unlink(mem_file_handle.as_str()) {
                        Ok(_) => return Ok(fd),

                        Err(errno) => {
                            return Err(errno.into());
                        }
                    },

                    Err(Errno::EXIST) => {
                        let time = SystemTime::now();

                        mem_file_handle = format!(
                            "/smithay-client-toolkit-{}",
                            time.duration_since(UNIX_EPOCH).unwrap().subsec_nanos()
                        );

                        continue;
                    }

                    Err(Errno::INTR) => continue,

                    Err(err) => return Err(err.into()),
                }
            }
        }
        #[cfg(target_os = "android")]
        {
            return Err(io::Error::from(Errno::NOSYS));
        }
    }"""
    if old_fallback not in text:
        sys.exit(f"sctk shm_open fallback not found in {p}")
    p.write_text(text.replace(old_fallback, new_fallback, 1))
    print("patched", p)


if __name__ == "__main__":
    main()
