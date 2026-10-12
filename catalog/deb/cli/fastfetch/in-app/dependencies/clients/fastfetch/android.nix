# fastfetch binary for Android NDK (fork/exec allowed).
args@{
  lib,
  pkgs,
  buildPackages,
  stdenv ? pkgs.stdenv,
  androidToolchain ? (import "${toolchainSrc}/dependencies/toolchains/android.nix" {
    inherit lib pkgs;
  }),
  toolchainSrc ? null,
  ...
}:

let
  inherit (args) lib pkgs buildPackages stdenv androidToolchain toolchainSrc;
  fastfetchSrc = import ./common.nix { inherit pkgs; };
in

pkgs.pkgs.stdenv.mkDerivation {
  pname = "fastfetch-android";
  version = "2.64.2";
  src = fastfetchSrc;

  nativeBuildInputs = with buildPackages; [
    cmake
    ninja
    pkg-config
    python3
  ];

  postPatch = ''
    cp ${./patches/apply-wawona-wayland-macos.py} ./apply-wawona-wayland-macos.py
    cp ${./patches/patch-fastfetch-android-glob.py} ./patch-fastfetch-android-glob.py
    cp ${./patches/processing_apple_mobile.c} ./processing_apple_mobile.c
    cp ${./patches/netif_apple_mobile.c} ./netif_apple_mobile.c
    cp ${./patches/localip_apple_mobile.c} ./localip_apple_mobile.c
    cp ${./patches/sound_apple_mobile.c} ./sound_apple_mobile.c
    cp ${./patches/codec_android_stub.c} ./codec_android_stub.c
    python3 apply-wawona-wayland-macos.py
    python3 patch-fastfetch-android-glob.py
    cp processing_apple_mobile.c src/common/impl/processing_linux.c
    cp netif_apple_mobile.c src/common/impl/netif_linux.c
    cp localip_apple_mobile.c src/detection/localip/localip_linux.c
    cp sound_apple_mobile.c src/detection/sound/sound_nosupport.c
    cp codec_android_stub.c src/detection/codec/codec_android.c
  '';

  configurePhase = ''
    runHook preConfigure
    unset NIX_CFLAGS_COMPILE NIX_LDFLAGS
    export CMAKE_OSX_ARCHITECTURES=
    export CMAKE_OSX_SYSROOT=
    export CMAKE_OSX_DEPLOYMENT_TARGET=
    cmake -S . -B build -G Ninja \
      -DCMAKE_SYSTEM_NAME=Android \
      -DCMAKE_ANDROID_NDK="${androidToolchain.androidndkRoot}" \
      -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a \
      -DCMAKE_ANDROID_STL_TYPE=c++_static \
      -DCMAKE_BUILD_TYPE=Release \
      -DBINARY_LINK_TYPE=dynamic \
      -DENABLE_VULKAN=OFF \
      -DENABLE_WAYLAND=OFF \
      -DENABLE_EGL=OFF \
      -DENABLE_GLX=OFF \
      -DENABLE_OPENCL=OFF \
      -DENABLE_GIO=OFF \
      -DENABLE_DCONF=OFF \
      -DENABLE_DBUS=OFF \
      -DENABLE_PULSE=OFF \
      -DENABLE_IMAGEMAGICK7=OFF \
      -DENABLE_IMAGEMAGICK6=OFF \
      -DENABLE_CHAFA=OFF \
      -DENABLE_LUA=OFF \
      -DENABLE_QUICKJS=OFF \
      -DENABLE_LIBZFS=OFF \
      -DENABLE_LTO=OFF
  '';

  buildPhase = ''
    runHook preBuild
    find build -type f \( -name 'build.ninja' -o -name 'link.txt' -o -name '*.rsp' \) -exec sed -i.bak 's/-Wl,--copy-dt-needed-entries//g' {} +
    ninja -C build fastfetch
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp build/fastfetch $out/bin/
  '';

  meta = with lib; {
    description = "fastfetch for Android";
    homepage = "https://github.com/fastfetch-cli/fastfetch";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
