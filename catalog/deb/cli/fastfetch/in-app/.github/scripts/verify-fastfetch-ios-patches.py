#!/usr/bin/env python3
"""Verify fastfetch Apple-mobile compliance patches still apply to upstream anchors.

Covers, in addition to the crash-fix stubs:
  * in-process process hygiene (sigaction/sigprocmask/atexit guarded)
  * exit() safety wrapper wired (forced-include + exit macro + entry rename)
  * re-enabled modules (LocalIp, GPU via Metal, host marketing-name, OS labels)
  * per-platform framework tiering + link hygiene (no IOKit; watchOS drops
    Metal/VideoToolbox) driven by the emitted nix-support manifest
  * banned syscalls across the authored mobile stub set
  * in-process lifecycle re-entry guards (idempotent destroy/init, per-run
    reset, defensive parseConfigFiles) that keep the singleton safe across
    repeated runs on the zsh pthread
  * Android real-binary recipe left decoupled (its own patch/stubs)
"""
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
CLIENT_DIR = ROOT / "dependencies" / "clients" / "fastfetch"
PATCH_DIR = CLIENT_DIR / "patches"
GEN_DIR = ROOT / "dependencies" / "generators"
URL = "https://github.com/fastfetch-cli/fastfetch/archive/refs/tags/2.64.2.tar.gz"

# App Store 2.5.2: no arbitrary code exec / dynamic loading / JIT on Apple mobile.
BANNED_IN_MOBILE = ("fork(", "execve", "execvp", "posix_spawn", "system(", "dlopen(", "MAP_JIT")

# Files we author/copy for the Apple-mobile build (scanned for banned syscalls).
AUTHORED_STUBS = (
    "processing_apple_mobile.c",
    "netif_apple_mobile.c",
    "displayserver_apple_mobile.c",
    "sound_apple_mobile.c",
    "smc_temps_apple_mobile.c",
    "cpu_apple_mobile.c",
    "host_apple_mobile.c",
    "os_apple_mobile.c",
    "gpu_apple_mobile.c",
    "codec_apple_mobile_stub.c",
    "wawona_ff_inprocess.c",
    "wawona_ff_inprocess.h",
)


def fail(msg: str) -> int:
    print(f"FAIL: {msg}", file=sys.stderr)
    return 1


def apply_patches(src: Path) -> None:
    for script in ("apply-wawona-wayland-macos.py", "patch-fastfetch-apple-mobile.py"):
        subprocess.check_call(["python3", str(PATCH_DIR / script)], cwd=src)
    # Mirror the source overrides done by apple-mobile.nix postPatch.
    for name, dest in (
        ("processing_apple_mobile.c", "src/common/impl/processing_linux.c"),
        ("netif_apple_mobile.c", "src/common/impl/netif_apple.c"),
        ("smc_temps_apple_mobile.c", "src/common/apple/smc_temps.c"),
        ("cpu_apple_mobile.c", "src/detection/cpu/cpu_apple.c"),
        ("host_apple_mobile.c", "src/detection/host/host_apple.c"),
        ("os_apple_mobile.c", "src/detection/os/os_apple.c"),
        ("gpu_apple_mobile.c", "src/detection/gpu/gpu_apple_mobile.c"),
        ("wawona_ff_inprocess.h", "src/wawona_ff_inprocess.h"),
        ("wawona_ff_inprocess.c", "src/wawona_ff_inprocess.c"),
    ):
        (src / dest).write_text((PATCH_DIR / name).read_text())


def check_patched_tree(src: Path) -> int:
    # --- crash-fix stubs (already shipped) ---
    mobile = (src / "src/common/impl/processing_linux.c").read_text()
    if "subprocess unavailable on Apple mobile" not in mobile:
        return fail("missing Apple-mobile spawn stub")
    general = (src / "src/options/general.c").read_text()
    if "WAWONA_APPLE_MOBILE_PRERUN" not in general:
        return fail("missing preRun guard")
    display = (src / "src/options/display.c").read_text()
    if "options->pipe = false" not in display or "options->disableLinewrap = true" not in display:
        return fail("display.c missing Apple-mobile forced TTY mode (colors + DECAWM off)")
    ds = (src / "src/detection/displayserver/displayserver_apple.c").read_text()
    if "WAYLAND_DISPLAY" not in ds:
        return fail("missing Wayland WM patch")
    smc = (src / "src/common/apple/smc_temps.c").read_text()
    if "SMC unavailable on Apple mobile" not in smc:
        return fail("missing Apple-mobile SMC stub")
    cpu = (src / "src/detection/cpu/cpu_apple.c").read_text()
    if "#include <IOKit" in cpu or "smc_temps.h" in cpu:
        return fail("cpu_apple.c still uses IOKit/SMC on Apple mobile")
    host = (src / "src/detection/host/host_apple.c").read_text()
    if "#include <IOKit" in host or "IORegistryEntry" in host:
        return fail("host_apple.c still uses IOKit on Apple mobile")

    # --- Phase 1: process hygiene ---
    init = (src / "src/common/impl/init.c").read_text()
    if "#if !defined(WAWONA_APPLE_MOBILE)\n    struct sigaction action;" not in init:
        return fail("init.c sigaction/sigprocmask not guarded by WAWONA_APPLE_MOBILE")
    if "sigprocmask(SIG_BLOCK, &newmask, NULL);\n#endif" not in init:
        return fail("init.c sigprocmask guard not closed")
    ffc = (src / "src/fastfetch.c").read_text()
    if "#if !defined(WAWONA_APPLE_MOBILE)\n    atexit(ffDestroyInstance);\n#endif" not in ffc:
        return fail("fastfetch.c atexit(ffDestroyInstance) not guarded")
    io = (src / "src/common/impl/io_unix.c").read_text()
    if "#if !defined(WAWONA_APPLE_MOBILE)\n        atexit(restoreTerm);\n#endif" not in io:
        return fail("io_unix.c atexit(restoreTerm) not guarded")

    # --- Phase 2: exit() wrapper ---
    shim_h = (src / "src/wawona_ff_inprocess.h").read_text()
    if "wawona_ff_inprocess_exit" not in shim_h or "wawona_ff_inprocess_run" not in shim_h:
        return fail("wawona_ff_inprocess.h missing shim API")
    shim_c = (src / "src/wawona_ff_inprocess.c").read_text()
    if "setjmp" not in shim_c or "longjmp" not in shim_c:
        return fail("wawona_ff_inprocess.c missing setjmp/longjmp barrier")
    if "int fastfetch_main(int argc, char** argv)" not in shim_c:
        return fail("wawona_ff_inprocess.c missing fastfetch_main wrapper")
    cmake = (src / "CMakeLists.txt").read_text()
    if "target_compile_definitions(libfastfetch PUBLIC WAWONA_APPLE_MOBILE=1)" not in cmake:
        return fail("CMakeLists missing WAWONA_APPLE_MOBILE compile definition")
    if "-include" not in cmake or "wawona_ff_inprocess.h" not in cmake:
        return fail("CMakeLists missing forced-include of the exit() shim")

    # --- Phase 3: enabled modules ---
    snippet = (PATCH_DIR / "cmake-apple-mobile-sources.snippet").read_text()
    if "src/wawona_ff_inprocess.c" not in snippet:
        return fail("snippet does not build the in-process wrapper")
    if "gpu_nosupport.c" in snippet or "src/detection/gpu/gpu_apple_mobile.c" not in snippet:
        return fail("GPU module not re-enabled (expected gpu_apple_mobile.c)")
    if "src/detection/localip/localip_linux.c" not in snippet:
        return fail("LocalIp module not enabled (expected localip_linux.c)")
    host_stub = (PATCH_DIR / "host_apple_mobile.c").read_text()
    if "hw.machine" not in host_stub or "iPhone" not in host_stub:
        return fail("host stub missing hw.machine marketing-name map")
    os_stub = (PATCH_DIR / "os_apple_mobile.c").read_text()
    for label in ("iPadOS", "tvOS", "watchOS", "visionOS"):
        if label not in os_stub:
            return fail(f"os stub missing {label} label")
    if 'ffStrbufSetStatic(&os->id, "macos")' not in os_stub:
        return fail("os stub must set os->id to macos for Apple logo detection")
    gpu_stub = (PATCH_DIR / "gpu_apple_mobile.c").read_text()
    if "MTLCreateSystemDefaultDevice" not in gpu_stub or "TARGET_OS_WATCH" not in gpu_stub:
        return fail("gpu stub must use Metal and self-stub on watchOS")

    # --- Phase 4: link hygiene / framework tiering ---
    # The mobile CMake link branch must not hardcode IOKit or VideoToolbox.
    mob_link = cmake.split("elseif(WAWONA_APPLE_MOBILE)\n    target_link_libraries")[1]
    mob_link = mob_link.split("elseif(APPLE)")[0]
    if "IOKit" in mob_link or "VideoToolbox" in mob_link:
        return fail("mobile CMake link still hardcodes IOKit/VideoToolbox")

    # --- Phase 5: in-process lifecycle re-entry guards ---
    # A fatal signal skips the post-run cleanup, so the wrapper also resets the
    # singleton before each run. Expect the reset both before setjmp and after.
    if shim_c.count("if (ffDestroyInstance) ffDestroyInstance();") < 2:
        return fail("wawona_ff_inprocess.c missing pre-run ffDestroyInstance reset")
    # ffDestroyInstance/ffInitInstance made idempotent via a live flag.
    if "ffInstanceLive" not in init:
        return fail("init.c missing ffInstanceLive re-entry guard")
    if "if (!ffInstanceLive)\n        return;" not in init:
        return fail("init.c ffDestroyInstance not guarded by ffInstanceLive")
    # ffPlatformInit frees prior resources before re-init on Apple mobile.
    plat = (src / "src/common/impl/FFPlatform.c").read_text()
    if "#if defined(WAWONA_APPLE_MOBILE)\n    ffPlatformDestroy(platform);" not in plat:
        return fail("FFPlatform.c ffPlatformInit missing destroy-first re-entry guard")
    # Defensive safety net: never iterate a torn/invalid configDirs.
    if "ffListDataIsValid" not in (src / "src/common/FFlist.h").read_text():
        return fail("FFlist.h missing ffListDataIsValid Apple-mobile guard")
    if "ffListDataIsValid(&instance.state.platform.configDirs)" not in ffc:
        return fail("fastfetch.c parseConfigFiles missing configDirs safety guard")
    if "ffListDataIsValid(&platform->configDirs)" not in plat:
        return fail("FFPlatform.c ffPlatformDestroy missing configDirs safety guard")
    # Host marketing map covers the current device (iPhone Air / iPhone18,4).
    if "iPhone18,4" not in host_stub or "iPhone Air" not in host_stub:
        return fail("host stub missing iPhone18,4 (iPhone Air) mapping")

    return 0


def check_nix_sources() -> int:
    am = (CLIENT_DIR / "apple-mobile.nix").read_text()
    if "isWatchOS" not in am or "fastfetch-frameworks" not in am:
        return fail("apple-mobile.nix missing per-platform framework tiering / manifest")
    if "hasMetal" not in am or "hasVideoToolbox" not in am:
        return fail("apple-mobile.nix missing Metal/VideoToolbox tiering")
    # watchOS must not receive Metal/VideoToolbox.
    if "lib.optionals hasVideoToolbox" not in am or "lib.optionals hasMetal" not in am:
        return fail("apple-mobile.nix framework list not gated on watchOS")

    ldflags = (GEN_DIR / "fastfetch-ldflags.nix").read_text()
    if "fastfetch-frameworks" not in ldflags or "IOKit" in ldflags:
        return fail("fastfetch-ldflags.nix must read the manifest and drop IOKit")
    return 0


def check_authored_stubs() -> int:
    for name in AUTHORED_STUBS:
        text = (PATCH_DIR / name).read_text()
        for token in BANNED_IN_MOBILE:
            if token in text:
                return fail(f"banned syscall {token!r} in authored stub {name}")
    return 0


def check_android_decoupled() -> int:
    android_patch = PATCH_DIR / "patch-fastfetch-android-glob.py"
    if not android_patch.exists():
        return fail("Android glob patch missing (recipe decoupling regressed)")
    apple_patch = (PATCH_DIR / "patch-fastfetch-apple-mobile.py").read_text()
    # A comment mentioning Android is fine; a file/path operation on Android
    # sources is a cross-recipe leak.
    for leak in ("_android", "patch-fastfetch-android", "android-glob", "ANDROID)"):
        if leak in apple_patch:
            return fail(f"Apple-mobile patch touches Android sources ({leak!r})")
    android = ROOT / "dependencies" / "clients" / "fastfetch" / "android.nix"
    if android.exists() and "WAWONA_APPLE_MOBILE" in android.read_text():
        return fail("android.nix must not define WAWONA_APPLE_MOBILE")
    return 0


def main() -> int:
    if check_authored_stubs():
        return 1
    if check_nix_sources():
        return 1
    if check_android_decoupled():
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        tgz = Path(tmp) / "src.tar.gz"
        urllib.request.urlretrieve(URL, tgz)
        subprocess.check_call(["tar", "-xzf", str(tgz), "-C", tmp])
        src = Path(tmp) / "fastfetch-2.64.2"
        apply_patches(src)
        if check_patched_tree(src):
            return 1
    print("fastfetch patch anchors OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
