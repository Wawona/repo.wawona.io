{ lib, stdenv, dpkg, coreutils }:

{ pname
, version
, src
, target ? "ios" # "ios" or "android"
, # Jailbreak layout for iOS packages. Rootful and rootless are different builds.
  jailbreakScheme ? "rootless" # "rootless" | "rootful" | "roothide"
, sileo ? {} # Reused for metadata
, patches ? []
, iosPatches ? []
, androidPatches ? []
, buildInputs ? []
, nativeBuildInputs ? []
, configureFlags ? []
, ...
} @ args:

let
  scheme = jailbreakScheme;
  iosPrefix =
    if scheme == "rootful" then "/"
    else if scheme == "roothide" then "/var/jb" # jbroot() at runtime; packaging under /var/jb layout
    else "/var/jb";
  iosArch =
    if scheme == "rootful" then "iphoneos-arm"
    else if scheme == "roothide" then (args.sileo.architecture or "iphoneos-arm64e")
    else (args.sileo.architecture or "iphoneos-arm64");

  # Explicit target validation and defaults
  targetData = if target == "android" then {
    prefix = "/data/data/com.termux/files/usr";
    arch = "aarch64";
    host = "aarch64-linux-android";
  } else if target == "ios" then {
    prefix = iosPrefix;
    arch = iosArch;
    host = "aarch64-apple-ios";
  } else throw "Wawona: Unsupported target '${target}'. Expecting 'ios' or 'android'.";

  prefix = args.prefix or targetData.prefix;
  arch = targetData.arch;
  host = targetData.host;

  allPatches = patches ++ (if target == "android" then androidPatches else if target == "ios" then iosPatches else []);

in
stdenv.mkDerivation (rec {
  inherit pname version src buildInputs;
  patches = allPatches;

  nativeBuildInputs = [ dpkg coreutils ] ++ (args.nativeBuildInputs or []);

  configureFlags = [
    "--prefix=${prefix}"
    "--host=${host}"
  ] ++ (args.configureFlags or []);

  postInstall = (args.postInstall or "") + ''
    # Prepare DEBIAN control file
    mkdir -p $out/DEBIAN
    cat > $out/DEBIAN/control <<EOF
Package: ${sileo.package or pname}
Version: ${version}
Architecture: ${arch}
Maintainer: ${sileo.maintainer or "Wawona Team <team@wawona.io>"}
Description: ${sileo.description or ((args.meta or {}).description or "Wawona utility")}
Section: ${sileo.section or "Utilities"}
Priority: ${sileo.priority or "optional"}
Homepage: ${sileo.homepage or ((args.meta or {}).homepage or "https://repo.wawona.io")}
EOF

    # iOS-specific RootHide tags
    if [ "${arch}" = "iphoneos-arm64e" ]; then
      echo "RootHide: true" >> $out/DEBIAN/control
      echo "Tag: role::tweak, roothide::compatible" >> $out/DEBIAN/control
    fi

    # Pack the debian package into the output
    mkdir -p $out/deb
    dpkg-deb -Zxz -b $out $out/deb/${pname}_${version}_${arch}.deb
  '';

} // (lib.filterAttrs (n: v: ! lib.elem n [ "sileo" "postInstall" "prefix" "target" "jailbreakScheme" ]) args))
