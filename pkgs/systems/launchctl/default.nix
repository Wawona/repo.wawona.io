# Procursus launchctl for Mode B iOS (Sileo APT).
#
# How (Procursus, not Apple launchd):
#   Apple's launchd stays the pid-1/session daemon. Agents and daemons are
#   still LaunchDaemons/LaunchAgents plists. ProcursusTeam/launchctl is a
#   BSD-2-Clause XPC client that speaks to that launchd (bootstrap/bootout/
#   load/unload/list/kickstart/...). It is not a second launchd.
#   Build: iphoneos arm64, macOS SDK header overlay (libproc.h, xpc),
#   ldid entitlements launchctl.xml (private xpc.launchd.*).
#   Upstream CI: ProcursusTeam/launchctl .github/workflows/build.yml
#   Packaging: Procursus makefiles/launchctl.mk -> bin/launchctl
#
# Where:
#   Source: github.com/ProcursusTeam/launchctl v1.2.0
#   Entitlements: Procursus build_misc/entitlements/launchctl.xml
#   This recipe: repo.wawona.io pkgs/systems/launchctl
#
# Never: App Store IPA, TrollStore tipa, or Mode A Wawona shell.

{ pkgs, mkWawonaPackage, target ? "ios", jailbreakScheme ? "rootless" }:

assert target == "ios";

let
  ents = ./launchctl.xml;
  ldid = pkgs.ldid-procursus;
in
mkWawonaPackage rec {
  pname = "wawona-launch-tools";
  version = "1.2.0";
  inherit jailbreakScheme;

  src = pkgs.fetchurl {
    url = "https://github.com/ProcursusTeam/launchctl/archive/refs/tags/v1.2.0.tar.gz";
    hash = "sha256-afwMFMONP5LxIVGMr/ERX+NP6EYH93BwBGN/2qWSUsg=";
  };

  nativeBuildInputs = [ ldid pkgs.python3 pkgs.gnused pkgs.findutils pkgs.gawk pkgs.gnumake ];

  dontConfigure = true;
  dontFixup = true;
  enableParallelBuilding = true;

  # Xcode iphoneos + macosx SDKs. Darwin sandbox must see Xcode.
  __noChroot = true;

  postPatch = ''
    awk '!/ldid /' Makefile > Makefile.nox && mv Makefile.nox Makefile
    for f in *.c *.h; do
      awk '{ gsub(/, bridgeOS [0-9.]+/, ""); print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    done
  '';

  buildPhase = ''
    runHook preBuild
    # nixpkgs apple-sdk DEVELOPER_DIR hides iphoneos. Use host Xcode.
    unset SDKROOT
    unset DEVELOPER_DIR
    saved_PATH="$PATH"
    export PATH="/usr/bin:/bin:$PATH"
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    SDK_IOS=$(xcrun --sdk iphoneos --show-sdk-path)
    SDK_MAC=$(xcrun --sdk macosx --show-sdk-path)
    test -n "$SDK_IOS"
    test -n "$SDK_MAC"
    mkdir -p "$TMPDIR/overlay/"{sys,mach}
    cp -a "$SDK_MAC/usr/include/launch.h" "$SDK_MAC/usr/include/libproc.h" "$TMPDIR/overlay/"
    cp -a "$SDK_MAC/usr/include/xpc" "$SDK_MAC/usr/include/net" "$TMPDIR/overlay/"
    cp -a "$SDK_MAC/usr/include/sys/proc_info.h" "$SDK_MAC/usr/include/sys/kern_control.h" "$TMPDIR/overlay/sys/"
    sed -E 's/__IOS_PROHIBITED|__TVOS_PROHIBITED|__WATCHOS_PROHIBITED//g' \
      < "$SDK_IOS/usr/include/mach/task.h" > "$TMPDIR/overlay/mach/task.h"
    python3 - <<'PY'
import pathlib, os
root = pathlib.Path(os.environ["TMPDIR"]) / "overlay" / "xpc"

def strip_macro(src, name):
    out = []
    i = 0
    n = len(name)
    while True:
        j = src.find(name, i)
        if j < 0:
            out.append(src[i:])
            break
        k = j + n
        while k < len(src) and src[k].isspace():
            k += 1
        if k >= len(src) or src[k] != "(":
            out.append(src[i:k])
            i = k
            continue
        depth = 0
        m = k
        while m < len(src):
            if src[m] == "(":
                depth += 1
            elif src[m] == ")":
                depth -= 1
                if depth == 0:
                    m += 1
                    break
            m += 1
        out.append(src[i:j])
        i = m
    return "".join(out)

for path in root.rglob("*.h"):
    text = path.read_text()
    text = strip_macro(text, "API_UNAVAILABLE_BEGIN")
    text = strip_macro(text, "API_UNAVAILABLE")
    text = text.replace("API_UNAVAILABLE_END", "")
    path.write_text(text)
PY
    export CC="$(xcrun --find clang)"
    export CFLAGS="-Wextra -Wno-unused-parameter -Os -arch arm64 -miphoneos-version-min=13.0 -isysroot $SDK_IOS -isystem $TMPDIR/overlay -fblocks"
    export LDFLAGS="-Os -miphoneos-version-min=13.0 -isysroot $SDK_IOS -arch arm64 -Wl,-undefined,dynamic_lookup"
    make -j''${NIX_BUILD_CORES:-1}
    export PATH="$saved_PATH"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    prefix="${if jailbreakScheme == "rootful" then "" else "/var/jb"}"
    mkdir -p "$out$prefix/usr/bin" "$out$prefix/bin" "$out$prefix/usr/share/doc/${pname}"
    install -m755 launchctl "$out$prefix/usr/bin/launchctl"
    ln -s ../usr/bin/launchctl "$out$prefix/bin/launchctl"
    install -m644 LICENSE "$out$prefix/usr/share/doc/${pname}/copyright"
    ldid -Icom.apple.xpc.launchctl -S${ents} -Cadhoc "$out$prefix/usr/bin/launchctl"
    runHook postInstall
  '';

  sileo = {
    package = "wawona-launch-tools";
    section = "System";
    description = "Procursus launchctl. Talks to host launchd. Mode B only.";
    homepage = "https://github.com/ProcursusTeam/launchctl";
    maintainers = [ "aspauldingcode" ];
    provides = "launchctl";
    conflicts = "launchctl";
    replaces = "launchctl";
  };

  meta = {
    description = "FOSS launchctl(1) for jailbroken iOS";
    homepage = "https://github.com/ProcursusTeam/launchctl";
    license = pkgs.lib.licenses.bsd2;
  };
}
