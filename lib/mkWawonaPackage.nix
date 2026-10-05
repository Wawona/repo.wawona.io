{ lib, stdenv, dpkg, coreutils }:

{ pname
, version
, src
, target ? "ios" # "ios" or "android"
, # iOS Sileo layout. Rootful and rootless are different builds.
  # null keeps sileo.architecture (existing recipes).
  jailbreakScheme ? null # "rootless" | "rootful" | "roothide"
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
  schemeArchTable = {
    rootless = "iphoneos-arm64"; # Dopamine / palera1n rootless. Sileo arch.
    rootful = "iphoneos-arm"; # checkra1n / unc0ver / palera1n rootful. Sileo arch.
    roothide = "iphoneos-arm64e";
  };
  schemeArch =
    if scheme == null then null
    else schemeArchTable.${scheme} or (throw "jailbreakScheme must be rootless, rootful, or roothide");
  requestedArch = sileo.architecture or null;
  iosArch =
    if schemeArch != null then schemeArch
    else if requestedArch != null then requestedArch
    else "iphoneos-arm64";
  iosPrefix = if scheme == "rootful" then "/" else "/var/jb";

  maintainersLib = import ./maintainers.nix;
  maintainerHandles = maintainersLib.requireHandles pname (sileo.maintainers or []);
  maintainerLines = map maintainersLib.debianLine maintainerHandles;
  maintainerField = builtins.head maintainerLines;
  uploadersField =
    if builtins.length maintainerLines > 1
    then lib.concatStringsSep ", " (lib.drop 1 maintainerLines)
    else null;

  # Explicit target validation and defaults.
  # Sileo picks the stanza whose Architecture matches the device dpkg arch.
  targetData =
    if scheme != null && target != "ios" then
      throw "jailbreakScheme is for iOS Sileo packages, not target '${target}'"
    else if scheme != null && requestedArch != null && requestedArch != schemeArch then
      throw "sileo.architecture ${requestedArch} does not match jailbreakScheme ${scheme} (${schemeArch})"
    else if target == "android" then {
      prefix = "/data/data/com.termux/files/usr";
      arch = "aarch64";
      host = "aarch64-linux-android";
    } else if target == "ios" then {
      prefix = iosPrefix;
      arch = iosArch;
      host = "aarch64-apple-ios";
    } else throw "Wawona: Unsupported target '${target}'. Expecting 'ios' or 'android'.";

  prefix =
    if scheme != null && args ? prefix && args.prefix != iosPrefix
    then throw "prefix ${args.prefix} does not match jailbreakScheme ${scheme} (${iosPrefix})"
    else args.prefix or targetData.prefix;
  arch = targetData.arch;
  host = targetData.host;

  allPatches = patches ++ (if target == "android" then androidPatches else if target == "ios" then iosPatches else []);

  # RootHide's Sileo fork reads these. Stock Sileo uses Architecture alone.
  rootHideControl = arch == "iphoneos-arm64e";
  sileoRoleTag = arch == "iphoneos-arm" || arch == "iphoneos-arm64";

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
Maintainer: ${maintainerField}
Author: ${maintainerField}
Description: ${sileo.description or ((args.meta or {}).description or "Wawona utility")}
Section: ${sileo.section or "Utilities"}
Priority: ${sileo.priority or "optional"}
Homepage: ${sileo.homepage or ((args.meta or {}).homepage or "https://repo.wawona.io")}
EOF
    ${lib.optionalString (uploadersField != null) ''
      echo "Uploaders: ${uploadersField}" >> $out/DEBIAN/control
    ''}
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

    # Pack the debian package into the output
    mkdir -p $out/deb
    dpkg-deb -Zxz -b $out $out/deb/${pname}_${version}_${arch}.deb
  '';

} // (lib.filterAttrs (n: v: ! lib.elem n [ "sileo" "postInstall" "prefix" "target" "jailbreakScheme" ]) args))
