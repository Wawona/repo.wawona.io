#!/usr/bin/env python3
"""Gate rustix::shm out of wayland-cursor on Android (memfd only)."""
import os
import pathlib
import sys

def find_vendor() -> pathlib.Path:
    env = os.environ.get("cargoDepsCopy", "").strip()
    if env:
        p = pathlib.Path(env)
        if p.is_dir() and list(p.glob("wayland-cursor-*/src/lib.rs")):
            return p
    top = pathlib.Path(os.environ.get("NIX_BUILD_TOP", "/build"))
    for pattern in ("niri-android-*-vendor", "*-vendor"):
        for cand in top.glob(pattern):
            if cand.is_dir() and list(cand.glob("wayland-cursor-*/src/lib.rs")):
                return cand
    # cargoSetupHook copies vendor next to the build cwd's parent.
    here = pathlib.Path.cwd()
    for cand in [here.parent / "niri-android-25.11-vendor", *here.parent.glob("*-vendor")]:
        if cand.is_dir() and list(cand.glob("wayland-cursor-*/src/lib.rs")):
            return cand
    sys.exit(
        "wayland-cursor vendor not found; "
        f"cargoDepsCopy={env!r} NIX_BUILD_TOP={os.environ.get('NIX_BUILD_TOP')!r} cwd={here}"
    )


root = find_vendor()
paths = list(root.glob("wayland-cursor-*/src/lib.rs"))
if not paths:
    sys.exit(f"wayland-cursor not in cargo vendor ({root})")
p = paths[0]
text = p.read_text()
text2 = text.replace(
    "use rustix::shm;\n",
    '#[cfg(not(target_os = "android"))]\nuse rustix::shm;\n',
)
if text2 == text:
    sys.exit("wayland-cursor: rustix::shm import not patched")

old = """    // Fallback to using shm_open.
    let sys_time = SystemTime::now();
    let mut mem_file_handle = format!(
        \"/wayland-cursor-rs-{}\",
        sys_time.duration_since(UNIX_EPOCH).unwrap().subsec_nanos()
    );
    loop {
        match shm::open(
            mem_file_handle.as_str(),
            shm::OFlags::CREATE | shm::OFlags::EXCL | shm::OFlags::RDWR,
            Mode::RUSR | Mode::WUSR,
        ) {
            Ok(fd) => match shm::unlink(mem_file_handle.as_str()) {
                Ok(_) => return Ok(fd),
                Err(errno) => return Err(IoError::from(errno)),
            },
            Err(Errno::EXIST) => {
                // If a file with that handle exists then change the handle
                mem_file_handle = format!(
                    \"/wayland-cursor-rs-{}\",
                    sys_time.duration_since(UNIX_EPOCH).unwrap().subsec_nanos()
                );
                continue;
            }
            Err(Errno::INTR) => continue,
            Err(errno) => return Err(IoError::from(errno)),
        }
    }
}"""

new = """    // Fallback to using shm_open (not on Android / Bionic).
    #[cfg(not(target_os = \"android\"))]
    {
        let sys_time = SystemTime::now();
        let mut mem_file_handle = format!(
            \"/wayland-cursor-rs-{}\",
            sys_time.duration_since(UNIX_EPOCH).unwrap().subsec_nanos()
        );
        loop {
            match shm::open(
                mem_file_handle.as_str(),
                shm::OFlags::CREATE | shm::OFlags::EXCL | shm::OFlags::RDWR,
                Mode::RUSR | Mode::WUSR,
            ) {
                Ok(fd) => match shm::unlink(mem_file_handle.as_str()) {
                    Ok(_) => return Ok(fd),
                    Err(errno) => return Err(IoError::from(errno)),
                },
                Err(Errno::EXIST) => {
                    mem_file_handle = format!(
                        \"/wayland-cursor-rs-{}\",
                        sys_time.duration_since(UNIX_EPOCH).unwrap().subsec_nanos()
                    );
                    continue;
                }
                Err(Errno::INTR) => continue,
                Err(errno) => return Err(IoError::from(errno)),
            }
        }
    }
    #[cfg(target_os = \"android\")]
    {
        return Err(IoError::from(Errno::NOSYS));
    }
}"""

if old not in text2:
    sys.exit("wayland-cursor: shm_open fallback block not found")
p.write_text(text2.replace(old, new))
print("patched", p)
