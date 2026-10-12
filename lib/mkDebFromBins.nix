# Pack already-built binaries into a .deb. No App Store patches.
# Used for wrapping upstream / nixpkgs process builds for jailbreak, Termux, Linux.
{ lib, stdenv, dpkg, coreutils }:

{ pname
, version
, # Path in the final filesystem layout (after prefix). Attrset of dest -> source file.
  # Example: { "bin/weston" = "${pkgs.weston}/bin/weston"; }
  files
, target ? "linux" # "ios" | "android" | "linux"
, jailbreakScheme ? null # "rootless" | "rootful" | "roothide" (ios only)
, sileo ? {}
, meta ? {}
}:

let
  scheme = jailbreakScheme;
  schemeArchTable = {
    rootless = "iphoneos-arm64";
    rootful = "iphoneos-arm";
    roothide = "iphoneos-arm64e";
  };
  schemeArch =
    if scheme == null then null
    else schemeArchTable.${scheme} or (throw "jailbreakScheme must be rootless, rootful, or roothide");

  linuxArch =
    if stdenv.hostPlatform.isAarch64 then "arm64"
    else if stdenv.hostPlatform.isx86_64 then "amd64"
    else throw "unsupported linux arch ${stdenv.hostPlatform.system}";

  iosPrefix = if scheme == "rootful" then "/" else "/var/jb";

  targetData =
    if scheme != null && target != "ios" then
      throw "jailbreakScheme is for iOS only"
    else if target == "android" then {
      prefix = "/data/data/com.termux/files/usr";
      arch = "aarch64";
    } else if target == "linux" then {
      prefix = "/usr";
      arch = linuxArch;
    } else if target == "ios" then {
      prefix = iosPrefix;
      arch = if schemeArch != null then schemeArch else (sileo.architecture or "iphoneos-arm64");
    } else throw "target must be ios, android, or linux";

  prefix = targetData.prefix;
  arch = targetData.arch;

  maintainersLib = import ./maintainers.nix;
  maintainerHandles = maintainersLib.requireHandles pname (sileo.maintainers or [ "aspauldingcode" ]);
  maintainerField = maintainersLib.debianLine (builtins.head maintainerHandles);

  rootHideControl = arch == "iphoneos-arm64e";
  sileoRoleTag = arch == "iphoneos-arm" || arch == "iphoneos-arm64";

  fileEntries = lib.mapAttrsToList (dest: src: { inherit dest src; }) files;
in
stdenv.mkDerivation {
  inherit pname version;
  dontUnpack = true;
  nativeBuildInputs = [ dpkg coreutils ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out${prefix}"
    ${lib.concatMapStrings (e: ''
      mkdir -p "$out${prefix}/$(dirname ${lib.escapeShellArg e.dest})"
      cp -a ${lib.escapeShellArg e.src} "$out${prefix}/${e.dest}"
      chmod +x "$out${prefix}/${e.dest}" || true
    '') fileEntries}

    mkdir -p $out/DEBIAN
    cat > $out/DEBIAN/control <<EOF
Package: ${sileo.package or pname}
Version: ${version}
Architecture: ${arch}
Maintainer: ${maintainerField}
Author: ${maintainerField}
Description: ${sileo.description or (meta.description or "Wawona Wayland package")}
Section: ${sileo.section or "Utilities"}
Priority: ${sileo.priority or "optional"}
Homepage: ${sileo.homepage or (meta.homepage or "https://wayland.freedesktop.org")}
EOF
    ${lib.optionalString ((sileo.depends or "") != "") ''
      echo "Depends: ${sileo.depends}" >> $out/DEBIAN/control
    ''}
    ${lib.optionalString rootHideControl ''
      echo "RootHide: true" >> $out/DEBIAN/control
      echo "Tag: role::tweak, roothide::compatible" >> $out/DEBIAN/control
    ''}
    ${lib.optionalString sileoRoleTag ''
      echo "Tag: role::developer" >> $out/DEBIAN/control
    ''}

    packdir=$(mktemp -d)
    shopt -s dotglob
    for item in "$out"/*; do
      case "$(basename "$item")" in
        deb) continue ;;
        *) cp -a "$item" "$packdir/" ;;
      esac
    done
    mkdir -p "$out/deb"
    dpkg-deb -Zxz --root-owner-group -b "$packdir" "$out/deb/${pname}_${version}_${arch}.deb"
    rm -rf "$packdir"
    runHook postInstall
  '';

  meta = meta // {
    description = meta.description or "Wawona Wayland package (process deb, no App Store patches)";
  };
}
