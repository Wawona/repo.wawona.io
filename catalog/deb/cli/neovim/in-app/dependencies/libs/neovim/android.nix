# Neovim binary for Android NDK (fork/exec allowed).
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
  neovimSrc = import ./common.nix { inherit pkgs; };
  version = import ./version.nix;
  ndkApi = toString androidToolchain.androidNdkApiLevel;
in
pkgs.stdenv.mkDerivation {
  pname = "neovim-android";
  inherit version;
  src = neovimSrc;

  __noChroot = true;
  dontConfigure = true;

  postPatch = ''
    cp ${./patches/patch-neovim-android-host-nlua.py} ./patch-neovim-android-host-nlua.py
    cp ${./patches/patch-neovim-android-deps.py} ./patch-neovim-android-deps.py
    python3 patch-neovim-android-host-nlua.py
    python3 patch-neovim-android-deps.py
  '';

  nativeBuildInputs = with buildPackages; [
    cmake
    ninja
    gnumake
    pkg-config
    python3
    lua5_1
    pkgs.gettext
  ];

  buildPhase = ''
    runHook preBuild
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    export CURL_CA_BUNDLE=$SSL_CERT_FILE
    export CMAKE_BUILD_TYPE=Release
    export CMAKE_OSX_ARCHITECTURES=
    export CMAKE_OSX_SYSROOT=
    export CMAKE_OSX_DEPLOYMENT_TARGET=
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    mkdir -p .deps/usr/bin
    ln -sf ${pkgs.lua5_1}/bin/lua .deps/usr/bin/lua
    ln -sf ${pkgs.lua5_1}/bin/luac .deps/usr/bin/luac

    echo "=== wwn-neovim: host nlua0 codegen pass ==="
    unset CC CXX DEPS_CMAKE_FLAGS
    make deps -j''${NIX_BUILD_CORES:-4}
    cmake -S . -B build-host -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH=$PWD/.deps/usr \
      -DENABLE_LIBINTL=OFF
    cmake --build build-host --target nlua0 -j''${NIX_BUILD_CORES:-4}
    HOST_NLUA=$(find build-host -path '*/lib/libnlua0.so' -print -quit)
    if [ -z "$HOST_NLUA" ] || [ ! -f "$HOST_NLUA" ]; then
      echo "host libnlua0.so missing after codegen pass" >&2
      exit 1
    fi
    mkdir -p host-artifacts
    cp "$HOST_NLUA" host-artifacts/libnlua0.so
    if [ -f .deps/usr/bin/luajit ]; then
      cp .deps/usr/bin/luajit host-artifacts/luajit-host
    fi
    rm -rf build-host .deps

    echo "=== wwn-neovim: Android cross-compile pass ==="
    export WAWONA_HOST_NLUA0="$PWD/host-artifacts/libnlua0.so"
    export WAWONA_GEN_CC="${androidToolchain.androidCC}"
    export CC="${androidToolchain.androidCC}"
    export CXX="${androidToolchain.androidCXX}"
    export DEPS_CMAKE_FLAGS="-DCMAKE_SYSTEM_NAME=Android -DCMAKE_SYSTEM_VERSION=${ndkApi} -DCMAKE_ANDROID_NDK=${androidToolchain.androidndkRoot} -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a -DCMAKE_ANDROID_STL_TYPE=c++_static -DCMAKE_C_COMPILER=${androidToolchain.androidCC} -DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX} -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY -DCMAKE_C_COMPILER_WORKS=1 -DCMAKE_CXX_COMPILER_WORKS=1 -DCMAKE_OSX_ARCHITECTURES= -DCMAKE_OSX_SYSROOT= -DCMAKE_OSX_DEPLOYMENT_TARGET= -DUSE_BUNDLED_LUAJIT=OFF -DUSE_BUNDLED_LUA=ON"
    make deps -j''${NIX_BUILD_CORES:-4}
    if [ -f host-artifacts/luajit-host ]; then
      ln -sf "$PWD/host-artifacts/luajit-host" .deps/usr/bin/luajit
      ln -sf "$PWD/host-artifacts/luajit-host" .deps/usr/bin/lua
    fi
    unset NIX_CFLAGS_COMPILE NIX_LDFLAGS
    DEPS_INC="$PWD/.deps/usr/include"
    DEPS_LIB="$PWD/.deps/usr/lib"
    LINK_FLAGS="--target=${androidToolchain.androidTarget}${ndkApi} --sysroot=${androidToolchain.androidNdkSysroot} -B${androidToolchain.androidNdkAbiLibDir} -L${androidToolchain.androidNdkAbiLibDir} -fPIE -pie"
    cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=Android \
      -DCMAKE_SYSTEM_VERSION=${ndkApi} \
      -DCMAKE_ANDROID_NDK=${androidToolchain.androidndkRoot} \
      -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a \
      -DCMAKE_ANDROID_STL_TYPE=c++_static \
      -DCMAKE_C_COMPILER=${androidToolchain.androidCC} \
      -DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX} \
      -DCMAKE_AR=${androidToolchain.androidAR} \
      -DCMAKE_RANLIB=${androidToolchain.androidRANLIB} \
      -DCMAKE_STRIP=${androidToolchain.androidSTRIP} \
      -DCMAKE_EXE_LINKER_FLAGS="$LINK_FLAGS" \
      -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      -DCMAKE_C_COMPILER_WORKS=ON \
      -DCMAKE_CXX_COMPILER_WORKS=ON \
      -DCMAKE_OSX_ARCHITECTURES= \
      -DCMAKE_OSX_SYSROOT= \
      -DCMAKE_OSX_DEPLOYMENT_TARGET= \
      -DUSE_LUAJIT=OFF \
      -DPREFER_LUA=ON \
      -DCMAKE_PREFIX_PATH=$PWD/.deps/usr \
      -DICONV_INCLUDE_DIR=${androidToolchain.androidNdkSysroot}/usr/include \
      -DENABLE_LIBINTL=OFF \
      -DENABLE_LANGUAGES=OFF \
      -DLIBUV_LIBRARY=$DEPS_LIB/libuv.a \
      -DLIBUV_INCLUDE_DIR=$DEPS_INC \
      -DLUV_LIBRARY=$DEPS_LIB/libluv.a \
      -DLUV_INCLUDE_DIR=$DEPS_INC \
      -DUNIBILIUM_LIBRARY=$DEPS_LIB/libunibilium.a \
      -DUNIBILIUM_INCLUDE_DIR=$DEPS_INC \
      -DLIBVTERM_LIBRARY=$DEPS_LIB/libvterm.a \
      -DLIBVTERM_INCLUDE_DIR=$DEPS_INC \
      -DMSGPACK_LIBRARY=$DEPS_LIB/libmsgpack-c.a \
      -DMSGPACK_INCLUDE_DIR=$DEPS_INC \
      -DTREESITTER_LIBRARY=$DEPS_LIB/libtree-sitter.a \
      -DTREESITTER_INCLUDE_DIR=$DEPS_INC \
      -DLPEG_LIBRARY=$DEPS_LIB/liblpeg.a \
      -DLUA_LIBRARY=$DEPS_LIB/liblua.a \
      -DLUA_INCLUDE_DIR=$DEPS_INC
    cmake --build build --target nvim_bin -j''${NIX_BUILD_CORES:-4}
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin $out/share/nvim
    cp build/bin/nvim $out/bin/
    cp -R runtime $out/share/nvim/
  '';

  meta = with lib; {
    description = "Neovim for Android (Wawona wwn-neovim port)";
    homepage = "https://neovim.io";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
