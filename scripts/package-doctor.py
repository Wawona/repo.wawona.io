#!/usr/bin/env python3
"""Check one package artifact. nix-build exit 0 is not a verdict.

Prints UNIT, VERDICT, REASON, EVIDENCE, SCOPE. At most three reasons.
Exit 0 is GREEN. Exit 1 is RED.
"""

from __future__ import annotations

import argparse
import os
import struct
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

EM_AARCH64 = 183
EM_X86_64 = 62
MAX_REASONS = 3


def record(unit: str, verdict: str, reasons: list[str], evidence: str, scope: str) -> int:
    shown = reasons[:MAX_REASONS]
    extra = len(reasons) - len(shown)
    if extra > 0:
        scope = f"{scope}; {extra} more reasons withheld"
    print(f"UNIT: {unit}")
    print(f"VERDICT: {verdict}")
    print("REASON: " + ("; ".join(shown) if shown else "checks passed"))
    print(f"EVIDENCE: {evidence}")
    print(f"SCOPE: {scope}")
    return 0 if verdict == "GREEN" else 1


def elf_machine(blob: bytes) -> int | None:
    if len(blob) < 20 or blob[:4] != b"\x7fELF":
        return None
    return struct.unpack_from("<H", blob, 18)[0]


def is_macho(blob: bytes) -> bool:
    if len(blob) < 4:
        return False
    magic = struct.unpack_from("<I", blob, 0)[0]
    return magic in (
        0xFEEDFACF,
        0xCEFAEDFE,
        0xFEEDFACE,
        0xCFFAEDFE,
        0xCAFEBABE,
        0xBEBAFECA,
        0xCAFEBABF,
        0xBFBAFECA,
    )


def is_wasm(blob: bytes) -> bool:
    return blob[:4] == b"\x00asm"


def file_brief(path: Path) -> str:
    try:
        out = subprocess.run(
            ["file", "-b", str(path)],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        return f"file(1) failed: {exc}"
    return (out.stdout or out.stderr or "").strip().split("\n", 1)[0][:240]


def deb_members(deb: Path) -> tuple[str, list[str]]:
    """Return control text and data-member names from a .deb (ar + tar)."""
    control = ""
    names: list[str] = []
    raw = deb.read_bytes()
    if not raw.startswith(b"!<arch>\n"):
        return control, names
    off = 8
    while off + 60 <= len(raw):
        header = raw[off : off + 60]
        name = header[0:16].decode("ascii", "replace").strip()
        size = int(header[48:58].decode("ascii").strip() or "0")
        body = raw[off + 60 : off + 60 + size]
        off += 60 + size
        if size % 2 == 1:
            off += 1
        if name.startswith("control.tar"):
            control = tar_member_text(body, "control")
        elif name.startswith("data.tar"):
            names = tar_member_names(body)
    return control, names


def tar_open(blob: bytes):
    import io

    bio = io.BytesIO(blob)
    for mode in ("r:gz", "r:xz", "r:bz2", "r:"):
        bio.seek(0)
        try:
            return tarfile.open(fileobj=bio, mode=mode)
        except tarfile.TarError:
            continue
    return None


def tar_member_text(blob: bytes, suffix: str) -> str:
    tf = tar_open(blob)
    if tf is None:
        return ""
    with tf:
        for member in tf.getmembers():
            if member.name.endswith(suffix) and member.isfile():
                extracted = tf.extractfile(member)
                if extracted is None:
                    continue
                return extracted.read().decode("utf-8", "replace")
    return ""


def tar_member_names(blob: bytes) -> list[str]:
    tf = tar_open(blob)
    if tf is None:
        return []
    with tf:
        return [m.name for m in tf.getmembers() if m.isfile() or m.issym()]


def extract_deb_file(deb: Path, member_suffix: str, dest: Path) -> bool:
    raw = deb.read_bytes()
    if not raw.startswith(b"!<arch>\n"):
        return False
    off = 8
    while off + 60 <= len(raw):
        header = raw[off : off + 60]
        name = header[0:16].decode("ascii", "replace").strip()
        size = int(header[48:58].decode("ascii").strip() or "0")
        body = raw[off + 60 : off + 60 + size]
        off += 60 + size
        if size % 2 == 1:
            off += 1
        if not name.startswith("data.tar"):
            continue
        tf = tar_open(body)
        if tf is None:
            return False
        with tf:
            for member in tf.getmembers():
                if not member.isfile():
                    continue
                if not member.name.endswith(member_suffix):
                    continue
                extracted = tf.extractfile(member)
                if extracted is None:
                    continue
                dest.write_bytes(extracted.read())
                return True
    return False


def control_field(control: str, key: str) -> str:
    prefix = key + ":"
    for line in control.splitlines():
        if line.startswith(prefix):
            return line.split(":", 1)[1].strip()
    return ""


def find_deb(out: Path) -> Path | None:
    if out.is_file() and out.suffix == ".deb":
        return out
    if out.is_dir():
        found = sorted((out / "deb").glob("*.deb")) if (out / "deb").is_dir() else []
        if found:
            return found[0]
        found = sorted(out.glob("*.deb"))
        if found:
            return found[0]
    return None


def pick_binary_name(names: list[str]) -> str | None:
    bins = [n for n in names if "/bin/" in n and not n.endswith(".so")]
    if bins:
        return bins[0]
    libs = [n for n in names if n.endswith(".so") or ".so." in n]
    return libs[0] if libs else None


def check_blob(blob: bytes, target: str, paths: list[str]) -> list[str]:
    reasons: list[str] = []
    machine = elf_machine(blob)
    head = blob[:65536]
    joined = "\n".join(paths)

    if target == "android":
        if machine != EM_AARCH64:
            reasons.append("android deb is not ELF aarch64")
        if b"ld-linux" in head or b"GLIBC_" in blob:
            reasons.append("android binary has glibc ld-linux or GLIBC_ symbols")
        if "/data/data/com.termux/files/usr/" not in joined:
            reasons.append("android files are not under the Termux prefix")
    elif target == "linux":
        if machine not in (EM_AARCH64, EM_X86_64):
            reasons.append("linux deb is not ELF aarch64 or x86_64")
        if b"/system/bin/linker64" in head or b"com.termux" in blob[:4096]:
            reasons.append("linux binary looks like Android Bionic or Termux")
        if not any(p.startswith("./usr/") or p.startswith("usr/") or "/usr/" in p for p in paths):
            reasons.append("linux files are not under /usr")
    elif target == "macos":
        if not is_macho(blob):
            reasons.append("macos artifact is not Mach-O")
    elif target.startswith("ios"):
        if not is_macho(blob):
            reasons.append("ios artifact is not Mach-O")
        if target == "ios-rootless" and "/var/jb/" not in joined:
            reasons.append("rootless files are not under /var/jb")
        if target == "ios-rootful" and any("/var/jb/" in p for p in paths):
            reasons.append("rootful files use the rootless prefix")
    elif target in ("wasi-p1", "wasi-p2", "wasix"):
        if not is_wasm(blob):
            reasons.append(f"{target} artifact is not wasm")
        if target == "wasi-p1" and b"wasix_" in blob:
            reasons.append("wasi-p1 artifact contains wasix_ imports")
        if target == "wasix" and b"wasix_" not in blob and b"wasmer" not in blob:
            reasons.append("wasix artifact has no wasix_ import")
    else:
        reasons.append(f"unknown target {target}")
    return reasons


def check_arch(control: str, target: str) -> list[str]:
    arch = control_field(control, "Architecture")
    if not arch:
        return []
    expect = {
        "android": "aarch64",
        "ios-rootless": "iphoneos-arm64",
        "ios-rootful": "iphoneos-arm",
        "ios-roothide": "iphoneos-arm64e",
    }.get(target)
    if expect and arch != expect:
        return [f"Architecture {arch} != {expect}"]
    if target == "linux" and arch not in ("arm64", "amd64", "aarch64", "x86_64"):
        return [f"linux Architecture {arch} is not arm64 or amd64"]
    return []


def runtime_reason(target: str) -> str | None:
    """Engine must be on PATH. Do not execute the module (a spin is not a proof)."""
    tool = "wasmer" if target == "wasix" else "wasmtime"
    try:
        proc = subprocess.run([tool, "--version"], check=False, capture_output=True, text=True)
    except OSError:
        return f"{tool} not on PATH"
    if proc.returncode != 0:
        return f"{tool} --version failed"
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check one Wawona package artifact")
    parser.add_argument("--target", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument(
        "--wayland",
        action="store_true",
        help="record that wayland was requested; instantiate is not a wayland proof",
    )
    args = parser.parse_args(argv)
    out = Path(args.out)
    unit = str(out)
    if not out.exists():
        return record(unit, "RED", [f"missing {out}"], "path does not exist", args.target)

    deb = find_deb(out)
    wayland_note = ""
    if args.wayland:
        wayland_note = " wayland flag set; socket traffic was not traced"

    if deb is not None:
        control, names = deb_members(deb)
        binary_name = pick_binary_name(names)
        reasons = check_arch(control, args.target)
        if binary_name is None:
            reasons.append("deb has no bin or shared library")
            return record(unit, "RED", reasons, f"deb {deb.name}", args.target + wayland_note)
        with tempfile.TemporaryDirectory() as tmp:
            blob_path = Path(tmp) / "blob"
            suffix = binary_name.split("/")[-1]
            if not extract_deb_file(deb, suffix, blob_path):
                reasons.append(f"could not extract {binary_name}")
                return record(unit, "RED", reasons, f"deb {deb.name}", args.target)
            blob = blob_path.read_bytes()
            reasons.extend(check_blob(blob, args.target, names))
            evidence = f"{deb.name} {binary_name} {file_brief(blob_path)}"
        if args.target in ("wasi-p1", "wasi-p2", "wasix"):
            runtime = runtime_reason(args.target)
            if runtime:
                reasons.append(runtime)
        verdict = "RED" if reasons else "GREEN"
        if args.wayland and verdict == "GREEN":
            verdict = "RED"
            reasons.append("wayland requested but no socket trace")
        return record(unit, verdict, reasons, evidence, args.target + wayland_note)

    blob = out.read_bytes() if out.is_file() else b""
    if not blob:
        return record(unit, "RED", ["no .deb and no file to read"], str(out), args.target)
    reasons = check_blob(blob, args.target, [str(out)])
    if args.target in ("wasi-p1", "wasi-p2", "wasix"):
        runtime = runtime_reason(args.target)
        if runtime:
            reasons.append(runtime)
    if args.wayland:
        reasons.append("wayland requested but no socket trace")
    verdict = "RED" if reasons else "GREEN"
    return record(unit, verdict, reasons, file_brief(out), args.target + wayland_note)


def mini_elf(machine: int, extra: bytes = b"") -> bytes:
    blob = bytearray(64)
    blob[0:4] = b"\x7fELF"
    blob[4] = 2
    blob[5] = 1
    blob[6] = 1
    struct.pack_into("<H", blob, 16, 3)
    struct.pack_into("<H", blob, 18, machine)
    struct.pack_into("<I", blob, 20, 1)
    return bytes(blob) + extra


def write_deb(path: Path, control: str, members: dict[str, bytes]) -> None:
    import io

    def tar_gz(files: dict[str, bytes]) -> bytes:
        bio = io.BytesIO()
        with tarfile.open(fileobj=bio, mode="w:gz") as tf:
            for name, data in files.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                tf.addfile(info, io.BytesIO(data))
        return bio.getvalue()

    control_blob = tar_gz({"./control": control.encode()})
    data_blob = tar_gz(members)

    def ar_member(name: str, payload: bytes) -> bytes:
        header = f"{name:<16}0           0     0     100644  {len(payload):<10}`\n".encode()
        pad = b"\n" if len(payload) % 2 else b""
        return header + payload + pad

    path.write_bytes(
        b"!<arch>\n"
        + ar_member("debian-binary", b"2.0\n")
        + ar_member("control.tar.gz", control_blob)
        + ar_member("data.tar.gz", data_blob)
    )


def selftest() -> int:
    """PACKAGE_DOCTOR_SELFTEST=1. No nix build."""
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        if main(["--target", "android", "--out", str(root / "nope")]) != 1:
            failures += 1
        junk = root / "junk"
        junk.write_bytes(b"not-elf")
        if main(["--target", "android", "--out", str(junk)]) != 1:
            failures += 1
        if not check_blob(b"\x00asmwasix_stub", "wasi-p1", ["m.wasm"]):
            failures += 1
        good = root / "good.deb"
        write_deb(
            good,
            "Package: demo\nArchitecture: aarch64\n",
            {"./data/data/com.termux/files/usr/bin/demo": mini_elf(EM_AARCH64)},
        )
        if main(["--target", "android", "--out", str(good)]) != 0:
            failures += 1
        glibc = root / "glibc.deb"
        write_deb(
            glibc,
            "Package: demo\nArchitecture: aarch64\n",
            {
                "./data/data/com.termux/files/usr/bin/demo": mini_elf(
                    EM_AARCH64, b"ld-linux-aarch64.so.1"
                )
            },
        )
        if main(["--target", "android", "--out", str(glibc)]) != 1:
            failures += 1
        if main(["--target", "android", "--wayland", "--out", str(good)]) != 1:
            failures += 1
        ls = Path("/bin/ls")
        if ls.exists() and is_macho(ls.read_bytes()):
            if main(["--target", "macos", "--out", str(ls)]) != 0:
                failures += 1
            if main(["--target", "android", "--out", str(ls)]) != 1:
                failures += 1
    if failures:
        print(f"SELFTEST failures={failures}", file=sys.stderr)
        return 1
    print("SELFTEST ok")
    return 0


if __name__ == "__main__":
    if os.environ.get("PACKAGE_DOCTOR_SELFTEST") == "1":
        sys.exit(selftest())
    sys.exit(main())
