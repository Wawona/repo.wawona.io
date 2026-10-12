# Neovim in-process static archive for Apple mobile (App Store–safe).
{
  lib,
  pkgs,
  buildPackages,
  iosToolchain,
  simulator ? false,
  xcodeUtils ? iosToolchain,
  toolchainSrc ? null,
  ...
}:

let
  mobile = (import "${toolchainSrc}/dependencies/toolchains/apple-mobile-platform.nix") {
    inherit iosToolchain simulator;
  };
  appleCmake = import "${toolchainSrc}/dependencies/toolchains/apple-cmake-toolchain.nix";
  neovimSrc = import ./common.nix { inherit pkgs; };
  version = import ./version.nix;
  helpers = import ./build-helpers.nix {
    inherit lib pkgs buildPackages neovimSrc version;
    appleMobile = true;
    inherit iosToolchain simulator xcodeUtils toolchainSrc;
  };
in
pkgs.stdenv.mkDerivation {
  pname = "neovim-apple-mobile";
  inherit version;
  src = neovimSrc;

  __noChroot = true;
  dontConfigure = true;

  nativeBuildInputs = helpers.baseNative ++ [
    xcodeUtils.findXcodeScript
    pkgs.gettext
  ];

  postPatch = helpers.applyAppleMobilePatches;

  buildPhase = ''
    runHook preBuild

    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      [ -n "$XCODE_APP" ] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    fi

    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    export CURL_CA_BUNDLE=$SSL_CERT_FILE

    ${helpers.hostCodegenPass}

    ${iosToolchain.mkIOSBuildEnv {
      inherit simulator;
      minVersion = mobile.minVersion;
    }}

    ${lib.optionalString mobile.isVisionOS ''
      # Neovim's bundled ExternalProject dependencies do not consistently
      # inherit CMAKE_TOOLCHAIN_FILE. CMake otherwise seeds their Darwin target
      # from the macOS host version (for example xros14.0, which is invalid).
      export MACOSX_DEPLOYMENT_TARGET="${mobile.minVersion}"
    ''}

    ${appleCmake { inherit iosToolchain simulator; }}

    ${helpers.iosCrossBuildPass}

    ${helpers.collectArchive}
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include $out/share/nvim
    cp libwawona-neovim.a $out/lib/
    cp -R runtime $out/share/nvim/
    cat > $out/include/wawona-neovim.h <<'EOF'
#ifndef WAWONA_NEOVIM_H
#define WAWONA_NEOVIM_H
int wawona_nvim_main(int argc, char **argv);
#endif
EOF
  '';

  meta = with lib; {
    description = "Neovim in-process archive for Apple mobile (App Store safe)";
    homepage = "https://neovim.io";
    license = licenses.asl20;
    platforms = platforms.darwin;
  };
}
