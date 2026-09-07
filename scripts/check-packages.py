#!/usr/bin/env python3
"""Gate for repo.wawona.io wasm + deb maintainers.

Identity is a GitHub username. Display names are queried from
api.github.com (never handwritten). Email lives in maintainers.json
because GitHub often hides it; Debian still needs Name <email>.

  python3 scripts/check-packages.py                 # CI (queries GitHub)
  python3 scripts/check-packages.py --sync          # write maintainers.resolved.json
  python3 scripts/check-packages.py --fix           # rewrite .deb control + Packages
  python3 scripts/check-packages.py --offline --root .  # flake / no network
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import lzma
import os
import re
import sys
import tarfile
import urllib.error
import urllib.request
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAINTAINERS = ROOT / "maintainers.json"
RESOLVED = ROOT / "maintainers.resolved.json"
WASM_INDEX = ROOT / "wasm/v1/index.json"
PACKAGES = ROOT / "Packages"
DEBS = ROOT / "debs"
PKGS = ROOT / "pkgs"
GITHUB_API = "https://api.github.com"
HANDLE_RE = re.compile(r"^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$")
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
DEBIAN_MAINT = re.compile(r"^(.+?) <([^>]+)>$")
AR_MAGIC = b"!<arch>\n"
AR_HEADER = 60


def bind_root(root: Path) -> None:
    global ROOT, MAINTAINERS, RESOLVED, WASM_INDEX, PACKAGES, DEBS, PKGS
    ROOT = root.resolve()
    MAINTAINERS = ROOT / "maintainers.json"
    RESOLVED = ROOT / "maintainers.resolved.json"
    WASM_INDEX = ROOT / "wasm/v1/index.json"
    PACKAGES = ROOT / "Packages"
    DEBS = ROOT / "debs"
    PKGS = ROOT / "pkgs"


def fail(errors: list[str]) -> None:
    for item in errors:
        print(f"FAIL {item}", file=sys.stderr)
    raise SystemExit(1 if errors else 0)


def load_json(path: Path) -> dict:
    if not path.is_file():
        print(f"FAIL missing {path}", file=sys.stderr)
        raise SystemExit(1)
    return json.loads(path.read_text(encoding="utf-8"))


def github_headers() -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "repo.wawona.io-check",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def github_user(login: str) -> dict:
    req = urllib.request.Request(f"{GITHUB_API}/users/{login}", headers=github_headers())
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GET /users/{login} -> HTTP {exc.code}: {body[:200]}") from exc


def iter_ar(data: bytes):
    if not data.startswith(AR_MAGIC):
        raise ValueError("not a debian ar archive")
    off = len(AR_MAGIC)
    while off + AR_HEADER <= len(data):
        hdr = data[off : off + AR_HEADER]
        if hdr.strip(b"\0") == b"":
            break
        name = hdr[0:16].decode("ascii", errors="replace").strip()
        size = int(hdr[48:58].decode("ascii").strip())
        off += AR_HEADER
        payload = data[off : off + size]
        off += size
        if size % 2:
            off += 1
        yield name, payload


def pack_ar(members: list[tuple[str, bytes]]) -> bytes:
    out = bytearray(AR_MAGIC)
    for name, payload in members:
        header_name = name[:16].ljust(16)
        size = str(len(payload)).rjust(10)
        header = (
            f"{header_name}{str(0).rjust(12)}{str(0).rjust(6)}"
            f"{str(0).rjust(6)}{str(0o100644).rjust(8)}{size}`\n"
        )
        out.extend(header.encode("ascii"))
        out.extend(payload)
        if len(payload) % 2:
            out.append(0x0A)
    return bytes(out)


def open_control_tar(blob: bytes, name: str) -> tarfile.TarFile:
    if name.endswith(".xz"):
        raw = lzma.decompress(blob)
        return tarfile.open(fileobj=io.BytesIO(raw), mode="r:")
    if name.endswith(".gz") or name.endswith(".tgz"):
        return tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz")
    return tarfile.open(fileobj=io.BytesIO(blob), mode="r:")


def deb_control_text(path: Path) -> str:
    members = dict(iter_ar(path.read_bytes()))
    key = next(k for k in members if k.startswith("control.tar"))
    with open_control_tar(members[key], key) as tf:
        for member in tf.getmembers():
            if member.name.endswith("control") and tf.extractfile(member):
                return tf.extractfile(member).read().decode("utf-8")
    raise ValueError(f"{path}: no control file")


def parse_control(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    key = None
    for line in text.splitlines():
        if not line:
            continue
        if line.startswith(" ") and key:
            fields[key] += "\n" + line[1:]
            continue
        if ":" in line:
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
    return fields


def set_control_field(text: str, field: str, value: str) -> str:
    pattern = re.compile(rf"^{re.escape(field)}:.*$", re.MULTILINE)
    line = f"{field}: {value}"
    if pattern.search(text):
        return pattern.sub(line, text, count=1)
    text = text.rstrip() + "\n"
    return text + line + "\n"


def write_control_tar_xz(control_text: str) -> bytes:
    payload = control_text.encode("utf-8")
    info = tarfile.TarInfo(name="./control")
    info.size = len(payload)
    info.mtime = 0
    info.mode = 0o644
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tf:
        dirinfo = tarfile.TarInfo(name=".")
        dirinfo.type = tarfile.DIRTYPE
        dirinfo.mode = 0o755
        dirinfo.mtime = 0
        tf.addfile(dirinfo)
        tf.addfile(info, io.BytesIO(payload))
    return lzma.compress(buf.getvalue(), format=lzma.FORMAT_XZ)


def rewrite_deb_control(path: Path, maintainer: str, author: str) -> None:
    members = list(iter_ar(path.read_bytes()))
    text = deb_control_text(path)
    text = set_control_field(text, "Maintainer", maintainer)
    text = set_control_field(text, "Author", author)
    new_control = write_control_tar_xz(text)
    updated = []
    replaced = False
    for name, payload in members:
        if name.startswith("control.tar"):
            updated.append(("control.tar.xz", new_control))
            replaced = True
        else:
            updated.append((name, payload))
    if not replaced:
        raise ValueError(f"{path}: missing control.tar")
    path.write_bytes(pack_ar(updated))


def debian_line(handle: str, roster: dict, resolved: dict) -> str:
    rec = roster[handle]
    name = resolved[handle]["name"]
    return f"{name} <{rec['email']}>"


def validate_roster(roster: dict) -> list[str]:
    errors: list[str] = []
    for handle, rec in roster.items():
        if not HANDLE_RE.match(handle):
            errors.append(f"maintainers.json: invalid GitHub login {handle!r}")
            continue
        if rec.get("github") != handle:
            errors.append(f"{handle}: github field must equal the object key")
        email = rec.get("email") or ""
        if not EMAIL_RE.match(email):
            errors.append(f"{handle}: email required and must be an address (Debian Maintainer)")
        github_id = rec.get("githubId")
        if not isinstance(github_id, int):
            errors.append(f"{handle}: githubId must be the numeric GitHub user id")
    return errors


def query_github(roster: dict) -> tuple[dict, list[str]]:
    errors = validate_roster(roster)
    resolved: dict[str, dict] = {}
    for handle, rec in roster.items():
        if not HANDLE_RE.match(handle):
            continue
        github_id = rec.get("githubId")
        if not isinstance(github_id, int):
            continue
        try:
            user = github_user(handle)
        except RuntimeError as exc:
            errors.append(str(exc))
            continue
        if user.get("type") != "User":
            errors.append(f"{handle}: GitHub type is {user.get('type')!r}, expected User")
        if user.get("id") != github_id:
            errors.append(
                f"{handle}: githubId {github_id} does not match live GitHub id {user.get('id')}. "
                "Query https://api.github.com/users/{handle}"
            )
        if (user.get("login") or "").lower() != handle.lower():
            errors.append(f"{handle}: GitHub login is {user.get('login')!r}")
        name = (user.get("name") or "").strip()
        if not name:
            errors.append(
                f"{handle}: GitHub profile has no name. Set the public name on github.com/{handle}"
            )
            continue
        resolved[handle] = {
            "github": user["login"],
            "githubId": user["id"],
            "name": name,
            "html_url": user.get("html_url") or f"https://github.com/{handle}",
            "avatar_url": user.get("avatar_url") or "",
        }
    return resolved, errors


def check_wasm(roster: dict) -> list[str]:
    errors: list[str] = []
    index = load_json(WASM_INDEX)
    if index.get("channel") != "wasm":
        errors.append("wasm/v1/index.json channel must be wasm")
    packages = index.get("packages")
    if not isinstance(packages, list) or not packages:
        errors.append("wasm/v1/index.json must list packages")
        return errors
    for pkg in packages:
        name = pkg.get("name") or "<unnamed>"
        handles = pkg.get("maintainers")
        if not isinstance(handles, list) or not handles:
            errors.append(f"wasm {name}: maintainers is required (GitHub usernames)")
            continue
        for handle in handles:
            if handle not in roster:
                errors.append(f"wasm {name}: unknown maintainer {handle!r}")
        for key in ("name", "version", "digest", "url", "summary"):
            if not pkg.get(key):
                errors.append(f"wasm {name}: missing {key}")
        url = str(pkg.get("url") or "")
        if ".deb" in url.lower() or "/jailbreak" in url.lower():
            errors.append(f"wasm {name}: blob URL must stay on the /wasm/ channel")
        digest = str(pkg.get("digest") or "")
        if digest and not digest.startswith("sha256:"):
            errors.append(f"wasm {name}: digest must be sha256:...")
    names = {pkg.get("name") for pkg in packages}
    if "hello-wasi" not in names:
        errors.append("wasm/v1/index.json must keep hello-wasi as the wpm smoke package")
    return errors


def check_nix_recipes() -> list[str]:
    errors: list[str] = []
    recipes = sorted(PKGS.glob("**/default.nix"))
    if not recipes:
        errors.append("no pkgs/**/default.nix recipes")
    for path in recipes:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        if "mkWawonaPackage" not in text:
            continue
        if not re.search(r"maintainers\s*=\s*\[", text):
            errors.append(f"{rel}: sileo.maintainers = [ \"github-login\" ] is required")
    return errors


def check_control_fields(label: str, fields: dict[str, str], roster: dict, resolved: dict) -> list[str]:
    errors: list[str] = []
    raw = fields.get("Maintainer") or ""
    match = DEBIAN_MAINT.match(raw)
    if not match:
        errors.append(f"{label}: Maintainer must be 'Full Name <email>' (got {raw!r})")
        return errors
    name, email = match.group(1).strip(), match.group(2).strip()
    hit = None
    for handle, rec in roster.items():
        if rec.get("email") == email:
            hit = handle
            break
    if hit is None:
        errors.append(f"{label}: Maintainer email {email!r} is not in maintainers.json")
        return errors
    expected_name = resolved.get(hit, {}).get("name")
    if expected_name and name != expected_name:
        errors.append(
            f"{label}: Maintainer name {name!r} must match live GitHub name {expected_name!r} for {hit}"
        )
    return errors


def check_packages_index(roster: dict, resolved: dict) -> list[str]:
    errors: list[str] = []
    if not PACKAGES.is_file():
        errors.append("Packages index missing")
        return errors
    text = PACKAGES.read_text(encoding="utf-8")
    stanzas = [s for s in re.split(r"\n\s*\n", text.strip()) if s.strip()]
    if not stanzas:
        errors.append("Packages index is empty")
    for stanza in stanzas:
        fields = parse_control(stanza)
        pkg = fields.get("Package") or "?"
        ver = fields.get("Version") or "?"
        arch = fields.get("Architecture") or "?"
        errors.extend(check_control_fields(f"Packages {pkg} {ver} {arch}", fields, roster, resolved))
        filename = fields.get("Filename") or ""
        if filename.endswith(".wasm") or "/wasm/" in filename:
            errors.append(f"Packages {pkg}: Filename must not mix wasm into the APT index")
        deb_path = ROOT / filename
        if filename and deb_path.is_file():
            data = deb_path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            if fields.get("SHA256") and fields["SHA256"] != digest:
                errors.append(f"Packages {pkg} {ver} {arch}: SHA256 does not match {filename}")
            if fields.get("Size") and fields["Size"] != str(len(data)):
                errors.append(f"Packages {pkg} {ver} {arch}: Size does not match {filename}")
    return errors


def check_search_pages() -> list[str]:
    errors: list[str] = []
    search = ROOT / "search" / "index.html"
    if not search.is_file():
        errors.append("search/index.html missing (human catalog lives at /search/)")
    else:
        text = search.read_text(encoding="utf-8")
        if 'id="door-wasm"' not in text or 'id="door-deb"' not in text:
            errors.append("search/index.html must offer separate Mode A wasm and Mode B deb doors")
        if "Mode A" not in text or "Mode B" not in text:
            errors.append("search/index.html must label Mode A (store-safe) and Mode B (jailbreak)")
        if re.search(r'type="radio"[^>]*name="channel"[^>]*value=""', text):
            errors.append("search/index.html must not offer a mixed All channel")
    js_path = ROOT / "search" / "catalog.js"
    if js_path.is_file():
        js = js_path.read_text(encoding="utf-8")
        if "wasmPkgs, ...deb" in js or "[...wasmPkgs, ...debPkgs]" in js:
            errors.append("search/catalog.js must not concatenate wasm and deb into one results list")
    wasm_html = ROOT / "wasm" / "index.html"
    if not wasm_html.is_file():
        errors.append("wasm/index.html missing")
    else:
        text = wasm_html.read_text(encoding="utf-8")
        if "/search/" not in text or "channel=wasm" not in text:
            errors.append("wasm/index.html must redirect humans to /search/?channel=wasm")
    if not (ROOT / "wasm" / "v1" / "index.json").is_file():
        errors.append("wasm/v1/index.json must remain for wpm (do not redirect the machine API)")
    deb_html = ROOT / "deb" / "index.html"
    if not deb_html.is_file():
        errors.append("deb/index.html missing")
    else:
        text = deb_html.read_text(encoding="utf-8")
        if "/search/" not in text or "channel=deb" not in text:
            errors.append("deb/index.html must redirect humans to /search/?channel=deb")
    jail_html = ROOT / "jailbreak" / "index.html"
    if not jail_html.is_file():
        errors.append("jailbreak/index.html missing (human landing; APT stays at repo root)")
    else:
        text = jail_html.read_text(encoding="utf-8")
        if "/search/" not in text or "channel=deb" not in text:
            errors.append("jailbreak/index.html must redirect humans to /search/?channel=deb")
        if "https://repo.wawona.io/" not in text:
            errors.append("jailbreak/index.html must say Sileo still uses https://repo.wawona.io/")
    not_found = ROOT / "404.html"
    if not not_found.is_file():
        errors.append("404.html missing (GitHub Pages unknown-path landing)")
    else:
        text = not_found.read_text(encoding="utf-8")
        if "/search/?channel=wasm" not in text or "/search/?channel=deb" not in text:
            errors.append("404.html must link both catalog lanes")
    for name in ("opensearch.xml", "opensearch-wasm.xml", "opensearch-deb.xml"):
        path = ROOT / "search" / name
        if not path.is_file():
            errors.append(f"search/{name} missing")
    setup = ROOT / "setup.sh"
    if setup.is_file():
        text = setup.read_text(encoding="utf-8")
        if "wwn-apt" in text:
            errors.append("setup.sh must not mention retired wwn-apt")
        if "wasm/v1" not in text and "wpm" not in text:
            errors.append("setup.sh must say store Wawona uses wpm / wasm/v1")
    return errors


def check_agent_skills() -> list[str]:
    errors: list[str] = []
    skills = (
        "repo-wawona-io-priors",
        "repo-wawona-io-catalogs",
        "repo-wawona-io-learn",
    )
    for name in skills:
        cursor = ROOT / ".cursor" / "skills" / name / "SKILL.md"
        docs = ROOT / "docs" / "agent-skills" / name / "SKILL.md"
        if not cursor.is_file():
            errors.append(f".cursor/skills/{name}/SKILL.md missing")
        elif f"name: {name}" not in cursor.read_text(encoding="utf-8"):
            errors.append(f".cursor/skills/{name}/SKILL.md must declare name: {name}")
        if not docs.is_file():
            errors.append(f"docs/agent-skills/{name}/SKILL.md missing (tracked mirror)")
    rule = ROOT / ".cursor" / "rules" / "repo-wawona-io-agent-learn.mdc"
    if not rule.is_file():
        errors.append(".cursor/rules/repo-wawona-io-agent-learn.mdc missing")
    else:
        text = rule.read_text(encoding="utf-8")
        if "alwaysApply: true" not in text:
            errors.append("repo-wawona-io-agent-learn.mdc must be alwaysApply")
        if "repo-wawona-io-priors" not in text:
            errors.append("repo-wawona-io-agent-learn.mdc must tell agents to read priors")
    return errors


def check_debs(roster: dict, resolved: dict) -> list[str]:
    errors: list[str] = []
    debs = sorted(DEBS.glob("*.deb")) if DEBS.is_dir() else []
    if not debs:
        errors.append("debs/ has no .deb files")
    for path in debs:
        try:
            fields = parse_control(deb_control_text(path))
        except Exception as exc:
            errors.append(f"{path.relative_to(ROOT)}: {exc}")
            continue
        errors.extend(check_control_fields(str(path.relative_to(ROOT)), fields, roster, resolved))
    return errors


def write_resolved(resolved: dict) -> None:
    payload = {
        "_comment": "Generated from api.github.com by scripts/check-packages.py --sync. Do not edit names by hand.",
        **resolved,
    }
    RESOLVED.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    print(f"wrote {RESOLVED.relative_to(ROOT)}")


def load_committed_resolved() -> dict:
    data = load_json(RESOLVED)
    return {k: v for k, v in data.items() if not k.startswith("_") and isinstance(v, dict)}


def update_release_hashes() -> None:
    packages = PACKAGES.read_bytes()
    gz_path = ROOT / "Packages.gz"
    gz_path.write_bytes(gzip.compress(packages, compresslevel=9, mtime=0))
    gz = gz_path.read_bytes()
    date = format_datetime(datetime.now(timezone.utc))
    md5_p = hashlib.md5(packages).hexdigest()
    md5_g = hashlib.md5(gz).hexdigest()
    sha_p = hashlib.sha256(packages).hexdigest()
    sha_g = hashlib.sha256(gz).hexdigest()
    text = f"""Origin: Wawona
Label: Wawona
Suite: stable
Codename: stable
Architectures: iphoneos-arm64 iphoneos-arm64e aarch64
Components: main
Description: Wawona System Utilities (iOS & Android)
Date: {date}
MD5Sum:
 {md5_p} {len(packages)} Packages
 {md5_g} {len(gz)} Packages.gz
SHA256:
 {sha_p} {len(packages)} Packages
 {sha_g} {len(gz)} Packages.gz
"""
    (ROOT / "Release").write_text(text, encoding="utf-8")
    (ROOT / "Releases").write_text(text, encoding="utf-8")


def stanza_with_deb_hashes(stanza: str) -> str:
    fields = parse_control(stanza)
    filename = fields.get("Filename") or ""
    path = ROOT / filename
    if not path.is_file():
        return stanza
    data = path.read_bytes()
    updates = {
        "Size": str(len(data)),
        "MD5sum": hashlib.md5(data).hexdigest(),
        "SHA1": hashlib.sha1(data).hexdigest(),
        "SHA256": hashlib.sha256(data).hexdigest(),
    }
    text = stanza
    for key, value in updates.items():
        text = set_control_field(text, key, value)
    return text


def fix_published_artifacts(roster: dict, resolved: dict) -> None:
    if not resolved:
        raise SystemExit("cannot --fix without GitHub-resolved names")
    handle = next(iter(roster))
    line = debian_line(handle, roster, resolved)
    for path in sorted(DEBS.glob("*.deb")):
        rewrite_deb_control(path, line, line)
        print(f"rewrote {path.relative_to(ROOT)}")
    raw = PACKAGES.read_text(encoding="utf-8")
    raw = re.sub(r"^Maintainer:.*$", f"Maintainer: {line}", raw, flags=re.MULTILINE)
    raw = re.sub(r"^Author:.*$", f"Author: {line}", raw, flags=re.MULTILINE)
    stanzas = [stanza_with_deb_hashes(s) for s in re.split(r"\n\s*\n", raw.strip()) if s.strip()]
    PACKAGES.write_text("\n\n".join(stanzas) + "\n", encoding="utf-8")
    update_release_hashes()
    print("updated Packages, Packages.gz, Release")


def package_errors(roster: dict, resolved: dict) -> list[str]:
    errors: list[str] = []
    errors.extend(check_wasm(roster))
    errors.extend(check_nix_recipes())
    errors.extend(check_packages_index(roster, resolved))
    errors.extend(check_debs(roster, resolved))
    errors.extend(check_search_pages())
    errors.extend(check_agent_skills())
    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sync", action="store_true", help="write maintainers.resolved.json from GitHub")
    parser.add_argument("--fix", action="store_true", help="rewrite published .deb Maintainer fields")
    parser.add_argument("--offline", action="store_true", help="skip GitHub; use committed maintainers.resolved.json")
    parser.add_argument("--root", type=Path, default=None, help="repository root (default: parent of scripts/)")
    args = parser.parse_args()
    bind_root(args.root or Path(__file__).resolve().parents[1])

    if args.offline and (args.sync or args.fix):
        fail(["--offline cannot be combined with --sync or --fix"])

    roster = load_json(MAINTAINERS)
    if not roster:
        fail(["maintainers.json is empty"])

    if args.offline:
        errors = validate_roster(roster)
        committed = load_committed_resolved() if RESOLVED.is_file() else {}
        for handle in roster:
            if HANDLE_RE.match(handle) and handle not in committed:
                errors.append(f"{handle}: missing from maintainers.resolved.json")
        if set(committed) - set(roster):
            extra = ", ".join(sorted(set(committed) - set(roster)))
            errors.append(f"maintainers.resolved.json has extra handles: {extra}")
        resolved = committed
        errors.extend(package_errors(roster, resolved))
        if errors:
            fail(errors)
        print(
            f"OK offline {len(roster)} GitHub maintainers, "
            f"{len(list(DEBS.glob('*.deb')))} debs"
        )
        return

    live, query_errors = query_github(roster)
    if args.sync:
        if query_errors:
            fail(query_errors)
        write_resolved(live)
        if not args.fix:
            return

    committed = load_committed_resolved() if RESOLVED.is_file() else {}
    errors = list(query_errors)
    if not args.sync:
        for handle, rec in live.items():
            got = committed.get(handle) or {}
            for key in ("github", "githubId", "name", "html_url"):
                if got.get(key) != rec.get(key):
                    errors.append(
                        f"{handle}: maintainers.resolved.json {key} is stale. "
                        "Run python3 scripts/check-packages.py --sync (GitHub is source of truth)"
                    )
        if set(committed) - set(roster):
            extra = ", ".join(sorted(set(committed) - set(roster)))
            errors.append(f"maintainers.resolved.json has extra handles: {extra}")

    resolved = live or committed
    errors.extend(package_errors(roster, resolved))

    if args.fix:
        if errors and not any("Maintainer" in e or "Author" in e or e.endswith(".deb") for e in errors):
            # still attempt maintainer rewrites
            pass
        fix_published_artifacts(roster, resolved)
        errors = []
        errors.extend(query_errors)
        errors.extend(package_errors(roster, resolved))

    if errors:
        fail(errors)
    print(
        f"OK {len(roster)} GitHub maintainers, "
        f"{len(list((ROOT / 'wasm/v1').glob('index.json')))} wasm index, "
        f"{len(list(DEBS.glob('*.deb')))} debs"
    )


if __name__ == "__main__":
    main()
