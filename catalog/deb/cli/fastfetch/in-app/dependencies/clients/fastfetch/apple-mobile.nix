# fastfetch in-process static archive for Apple mobile (App Store–safe).
{
  lib,
  pkgs,
  buildPackages,
  iosToolchain,
  simulator ? false,
  xcodeUtils ? iosToolchain,
  toolchainSrc ? null,
  fastfetchSrc,
  ...
}:

let
  mobile = (import "${toolchainSrc}/dependencies/toolchains/apple-mobile-platform.nix") {
    inherit iosToolchain simulator;
  };
  appleCmake = import "${toolchainSrc}/dependencies/toolchains/apple-cmake-toolchain.nix";

  # Per-platform capability tiering. watchOS has neither Metal nor VideoToolbox,
  # so the Metal-backed GPU module and VideoToolbox-backed codec module are
  # unavailable there and their sources/frameworks must be dropped.
  isWatchOS = mobile.isWatchOS or false;
  hasMetal = !isWatchOS; # iOS, iPadOS, tvOS, visionOS
  hasVideoToolbox = !isWatchOS;

  # Single source of truth for the frameworks the host app must link when it
  # -force_load's libfastfetch.a. Emitted to $out/nix-support/fastfetch-frameworks
  # so Wawona's xcodegen and fastfetch-ldflags.nix never hardcode per-platform
  # framework knowledge. IOKit is intentionally omitted: all IORegistry/SMC
  # detection paths are stubbed on Apple mobile.
  fastfetchFrameworks =
    [ "CoreFoundation" "Foundation" ]
    ++ lib.optionals hasVideoToolbox [ "VideoToolbox" ]
    ++ lib.optionals hasMetal [ "Metal" ];

  platformDefine =
    if isWatchOS then "-DWAWONA_APPLE_WATCHOS=1"
    else if (mobile.isTVOS or false) then "-DWAWONA_APPLE_TVOS=1"
    else if (mobile.isVisionOS or false) then "-DWAWONA_APPLE_VISIONOS=1"
    else "-DWAWONA_APPLE_IOS=1";

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DBINARY_LINK_TYPE=static"
    "-DBUILD_TESTS=OFF"
    "-DENABLE_VULKAN=OFF"
    "-DENABLE_SQLITE3=OFF"
    "-DENABLE_IMAGEMAGICK7=OFF"
    "-DENABLE_IMAGEMAGICK6=OFF"
    "-DENABLE_CHAFA=OFF"
    "-DENABLE_DRM=OFF"
    "-DENABLE_EGL=OFF"
    "-DENABLE_GLVND=OFF"
    "-DENABLE_OPENCL=OFF"
    "-DENABLE_RPM=OFF"
    "-DENABLE_DPKG=OFF"
    "-DENABLE_PACMAN=OFF"
    "-DENABLE_I3=OFF"
    "-DENABLE_DCONF=OFF"
    "-DENABLE_DBUS=OFF"
    "-DENABLE_ZFS=OFF"
    "-DENABLE_ZLIB=OFF"
    "-DENABLE_LIBZFS=OFF"
    "-DENABLE_WORDEXP=OFF"
    "-DENABLE_LUA=OFF"
    "-DENABLE_QUICKJS=OFF"
    "-DWAWONA_APPLE_MOBILE=1"
  ];
in
pkgs.stdenv.mkDerivation {
  pname = "fastfetch-apple-mobile";
  version = "2.64.2";

  src = fastfetchSrc;

  __noChroot = true;
  dontConfigure = true;

  nativeBuildInputs = with buildPackages; [
    cmake
    ninja
    pkg-config
    python3
    xcodeUtils.findXcodeScript
  ];

  postPatch = ''
    cp ${./patches/apply-wawona-wayland-macos.py} ./apply-wawona-wayland-macos.py
    cp ${./patches/patch-fastfetch-apple-mobile.py} ./patch-fastfetch-apple-mobile.py
    cp ${./patches/cmake-apple-mobile-sources.snippet} ./cmake-apple-mobile-sources.snippet
    cp ${./patches/processing_apple_mobile.c} ./processing_apple_mobile.c
    cp ${./patches/netif_apple_mobile.c} ./netif_apple_mobile.c
    cp ${./patches/displayserver_apple_mobile.c} ./displayserver_apple_mobile.c
    cp ${./patches/sound_apple_mobile.c} ./sound_apple_mobile.c
    cp ${./patches/smc_temps_apple_mobile.c} ./smc_temps_apple_mobile.c
    cp ${./patches/cpu_apple_mobile.c} ./cpu_apple_mobile.c
    cp ${./patches/host_apple_mobile.c} ./host_apple_mobile.c
    cp ${./patches/os_apple_mobile.c} ./os_apple_mobile.c
    cp ${./patches/gpu_apple_mobile.c} ./gpu_apple_mobile.c
    cp ${./patches/wawona_ff_inprocess.h} ./wawona_ff_inprocess.h
    cp ${./patches/wawona_ff_inprocess.c} ./wawona_ff_inprocess.c
    python3 apply-wawona-wayland-macos.py
    python3 patch-fastfetch-apple-mobile.py
    cp processing_apple_mobile.c src/common/impl/processing_linux.c
    cp netif_apple_mobile.c src/common/impl/netif_apple.c
    cp smc_temps_apple_mobile.c src/common/apple/smc_temps.c
    cp cpu_apple_mobile.c src/detection/cpu/cpu_apple.c
    cp host_apple_mobile.c src/detection/host/host_apple.c
    cp os_apple_mobile.c src/detection/os/os_apple.c
    cp gpu_apple_mobile.c src/detection/gpu/gpu_apple_mobile.c
    cp displayserver_apple_mobile.c src/detection/displayserver/displayserver_apple.c
    cp sound_apple_mobile.c src/detection/sound/sound_nosupport.c
    cp wawona_ff_inprocess.h src/wawona_ff_inprocess.h
    cp wawona_ff_inprocess.c src/wawona_ff_inprocess.c
  '' + lib.optionalString isWatchOS ''
    # watchOS: no VideoToolbox -> replace the VideoToolbox-based codec detector.
    cp ${./patches/codec_apple_mobile_stub.c} src/detection/codec/codec_apple.c
  '';

  buildPhase = ''
    runHook preBuild

    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      [ -n "$XCODE_APP" ] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    fi
  '' + (iosToolchain.mkIOSBuildEnv {
    inherit simulator;
    minVersion = mobile.minVersion;
  }) + (appleCmake { inherit iosToolchain simulator; }) + ''
    # .m is the OBJC language. C flags do not apply. Without the deployment
    # min, clang uses the iPhoneOS SDK version and emits _objc_release_xN,
    # which libobjc lacks before iOS 16.
    if ! grep -q 'CMAKE_OBJC_FLAGS' ios-toolchain.cmake; then
      cat >> ios-toolchain.cmake <<EOF
set(CMAKE_OBJC_COMPILER "$XCODE_CLANG")
set(CMAKE_OBJCXX_COMPILER "$XCODE_CLANGXX")
set(CMAKE_OBJC_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC -fobjc-arc -Wno-unknown-warning-option")
set(CMAKE_OBJCXX_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC -fobjc-arc -Wno-unknown-warning-option")
EOF
    fi
    cmake -S . -B build -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE=$PWD/ios-toolchain.cmake \
      ${lib.concatStringsSep " " cmakeFlags}
    ninja -C build libfastfetch

    OBJ_DIR=build/CMakeFiles/libfastfetch.dir
    # fastfetch.c is the CLI entry (not part of the libfastfetch target). Compile
    # it as fastfetch_main_impl and let wawona_ff_inprocess.c provide the public
    # fastfetch_main wrapper (setjmp barrier + exit() redirect + per-run cleanup).
    # Force-include the shim and define WAWONA_APPLE_MOBILE so the exit() macro and
    # the atexit guard both apply here too.
    $XCODE_CLANG -c src/fastfetch.c \
      -I. -Ibuild -Isrc \
      -arch $IOS_ARCH -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC -O2 \
      -DWAWONA_APPLE_MOBILE=1 ${platformDefine} \
      -D_GNU_SOURCE -D_XOPEN_SOURCE -D__STDC_WANT_LIB_EXT1__ -D_FILE_OFFSET_BITS=64 -D_DARWIN_C_SOURCE -DNDEBUG \
      -include src/wawona_ff_inprocess.h \
      -DFASTFETCH_TARGET_BINARY_NAME=fastfetch -Dmain=fastfetch_main_impl \
      -o fastfetch_main.o

    find "$OBJ_DIR" -name '*.o' -print > objlist.txt
    $DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar rcs libfastfetch.a \
      $(cat objlist.txt) fastfetch_main.o

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include $out/nix-support
    cp libfastfetch.a $out/lib/
    cat > $out/include/fastfetch.h <<'EOF'
#ifndef WAWONA_FASTFETCH_H
#define WAWONA_FASTFETCH_H
int fastfetch_main(int argc, char *argv[]);
#endif
EOF
    # Single source of truth for host-app framework linking (per platform).
    cat > $out/nix-support/fastfetch-frameworks <<'EOF'
${lib.concatStringsSep "\n" fastfetchFrameworks}
EOF
  '';

  meta = with lib; {
    description = "fastfetch in-process archive for Apple mobile (App Store safe)";
    homepage = "https://github.com/fastfetch-cli/fastfetch";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
