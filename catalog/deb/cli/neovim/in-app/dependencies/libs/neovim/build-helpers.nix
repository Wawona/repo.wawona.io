# Shared Neovim build helpers for macOS, Android, and Apple mobile.
{
  lib,
  pkgs,
  buildPackages,
  neovimSrc,
  version,
  appleMobile ? false,
  androidToolchain ? null,
  iosToolchain ? null,
  simulator ? false,
  xcodeUtils ? null,
  toolchainSrc ? null,
}:

let
  inherit (pkgs) stdenv;
  applePlatform =
    if iosToolchain.isVisionOSToolchain or false then (if simulator then 12 else 11)
    else if iosToolchain.isWatchOSToolchain or false then (if simulator then 9 else 4)
    else if iosToolchain.isTVOSToolchain or false then (if simulator then 8 else 3)
    else if simulator then 7 else 2;

  patchDir = ./patches;

  applyAppleMobilePatches = ''
    cp ${patchDir}/patch-neovim-apple-mobile.py ./patch-neovim-apple-mobile.py
    cp ${patchDir}/patch-libuv-spawn.py ./patch-libuv-spawn.py
    cp ${patchDir}/patch-lua-loslib-apple-mobile.py ./patch-lua-loslib-apple-mobile.py
    cp ${patchDir}/patch-and-build-lua-apple-mobile.sh ./patch-and-build-lua-apple-mobile.sh
    chmod +x ./patch-and-build-lua-apple-mobile.sh
    cp ${patchDir}/cmake-apple-mobile-flags.snippet ./cmake-apple-mobile-flags.snippet
    cp ${patchDir}/cmake-deps-apple-mobile.snippet ./cmake-deps-apple-mobile.snippet
    cp ${patchDir}/patch-neovim-link-collisions.py ./patch-neovim-link-collisions.py
    cp ${patchDir}/wwn-neovim-eval-stubs.c ./wwn-neovim-eval-stubs.c
    python3 patch-neovim-apple-mobile.py
    python3 patch-neovim-link-collisions.py
  '';

  baseNative = with buildPackages; [
    cmake
    ninja
    gnumake
    pkg-config
    python3
    lua5_1
  ];

  macNative = baseNative ++ (lib.optional (stdenv.hostPlatform.isDarwin) pkgs.gettext);

  cmakeExtraMac = lib.concatStringsSep " " [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DUSE_LUAJIT=ON"
    "-DLIBINTL_LIBRARY=${pkgs.gettext}/lib/libintl${pkgs.stdenv.targetPlatform.extensions.sharedLibrary}"
    "-DLIBINTL_INCLUDE_DIR=${pkgs.gettext}/include"
  ];

  cmakeExtraAppleMobile = lib.concatStringsSep " " [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DWAWONA_APPLE_MOBILE=ON"
    "-DUSE_LUAJIT=OFF"
    "-DPREFER_LUA=ON"
    "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF"
  ];

  depsCmakeExtraAppleMobile = lib.concatStringsSep " " [
    "-DWAWONA_APPLE_MOBILE=ON"
    "-DUSE_BUNDLED_LUAJIT=OFF"
    "-DUSE_BUNDLED_LUA=ON"
  ];

  hostCodegenPass = ''
    echo "=== wwn-neovim: host codegen pass (macOS native libnlua0) ==="
    export CMAKE_BUILD_TYPE=Release
    export CMAKE_EXTRA_FLAGS="${cmakeExtraAppleMobile} -DCMAKE_PREFIX_PATH=$PWD/.deps/usr"
    export DEPS_CMAKE_FLAGS="${depsCmakeExtraAppleMobile}"
    mkdir -p .deps/usr/bin
    ln -sf ${pkgs.lua5_1}/bin/lua .deps/usr/bin/lua
    ln -sf ${pkgs.lua5_1}/bin/luac .deps/usr/bin/luac
    make deps DEPS_CMAKE_FLAGS="$DEPS_CMAKE_FLAGS" -j''${NIX_BUILD_CORES:-4}
    make build/.ran-cmake CMAKE_EXTRA_FLAGS="$CMAKE_EXTRA_FLAGS"
    ${pkgs.cmake}/bin/cmake --build build --target nlua0 -j''${NIX_BUILD_CORES:-4}
    mkdir -p host-artifacts
    HOST_NLUA=$(find build -path '*/lib/libnlua0.so' -print -quit)
    if [ -z "$HOST_NLUA" ] || [ ! -f "$HOST_NLUA" ]; then
      echo "host libnlua0.so missing after codegen pass" >&2
      exit 1
    fi
    cp "$HOST_NLUA" host-artifacts/libnlua0.so
    rm -rf build .deps
  '';

  iosCrossBuildPass = ''
    echo "=== wwn-neovim: iOS cross-compile pass ==="
    export WAWONA_HOST_NLUA0="$PWD/host-artifacts/libnlua0.so"
    export CMAKE_BUILD_TYPE=Release
    export CMAKE_EXTRA_FLAGS="${cmakeExtraAppleMobile} -DCMAKE_TOOLCHAIN_FILE=$PWD/ios-toolchain.cmake -DCMAKE_PREFIX_PATH=$PWD/.deps/usr"
    export DEPS_CMAKE_FLAGS="${depsCmakeExtraAppleMobile} -DCMAKE_TOOLCHAIN_FILE=$PWD/ios-toolchain.cmake"
    cat >> ios-toolchain.cmake <<'EOF'
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
EOF
    mkdir -p .deps/usr/bin
    ln -sf ${pkgs.lua5_1}/bin/lua .deps/usr/bin/lua
    ln -sf ${pkgs.lua5_1}/bin/luac .deps/usr/bin/luac
    make deps DEPS_CMAKE_FLAGS="$DEPS_CMAKE_FLAGS" -j''${NIX_BUILD_CORES:-4}
    LUA_MAKEFILE=$(find .deps/build -path '*/lua/src/Makefile' -print -quit)
    if [ -n "$LUA_MAKEFILE" ]; then
      LUA_DIR=$(dirname "$LUA_MAKEFILE")
      echo "Rebuilding bundled PUC Lua for Apple mobile ($XCODE_CLANG)"
      CC="$XCODE_CLANG" AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar" \
        RANLIB="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ranlib" \
        bash "$PWD/patch-and-build-lua-apple-mobile.sh" "$LUA_DIR" "$PWD/.deps/usr" make \
          "-arch ''${IOS_ARCH:-arm64} -target ''${APPLE_LINKER_TARGET} -isysroot ''${SDKROOT} ''${APPLE_DEPLOYMENT_FLAG} -O2 -g3 -fPIC"
      mkdir -p .deps/usr/lib
      cp "$LUA_DIR/liblua.a" .deps/usr/lib/liblua.a
    fi
    if ! make CMAKE_EXTRA_FLAGS="$CMAKE_EXTRA_FLAGS" -j''${NIX_BUILD_CORES:-4}; then
      if [ ! -f build/src/nvim/CMakeFiles/nvim_bin.dir/main.c.o ]; then
        echo "iOS cross-compile failed before nvim objects were built" >&2
        exit 1
      fi
      echo "wwn-neovim: nvim link failed as expected (libuv Unix libs); finishing nvim objects"
    fi
    ${pkgs.ninja}/bin/ninja -C build -k 0 2>/dev/null || true
  '';

  collectArchive = ''
    keepAppleMobileObject() {
      local obj="$1"
      local plat
      plat=$(${pkgs.darwin.cctools}/bin/otool -l "$obj" 2>/dev/null | awk '
        /cmd LC_BUILD_VERSION/ { build = 1; next }
        build && $1 == "platform" { result = $2; build = 0 }
        /cmd LC_VERSION_MIN_IPHONEOS/ { result = 2 }
        /cmd LC_VERSION_MIN_TVOS/ { result = 3 }
        /cmd LC_VERSION_MIN_WATCHOS/ { result = 4 }
        END { if (result != "") print result }
      ')
      [ "$plat" = "${toString applePlatform}" ]
    }

    WORKDIR=$(mktemp -d)
    SRC_ROOT="$PWD"
    for lib in "$SRC_ROOT"/.deps/usr/lib/*.a; do
      [ -f "$lib" ] || continue
      libname=$(basename "$lib" .a)
      TMP_LIB=$(mktemp -d)
      (cd "$TMP_LIB" && ar x "$lib")
      for obj in "$TMP_LIB"/*.o; do
        [ -f "$obj" ] || continue
        if keepAppleMobileObject "$obj"; then
          cp -n "$obj" "$WORKDIR/deps_''${libname}_$(basename "$obj")"
        fi
      done
      rm -rf "$TMP_LIB"
    done
    while IFS= read -r obj; do
      rel="''${obj#*nvim_bin.dir/}"
      safe="nvim_''${rel//\//_}"
      cp -f "$obj" "$WORKDIR/$safe"
    done < <(find build -path '*/nvim_bin.dir/*.o' -print)
    MAIN_OBJ="$WORKDIR/nvim_main.c.o"
    if [ ! -f "$MAIN_OBJ" ]; then
      echo "main.c.o missing in archive workdir" >&2
      exit 1
    fi
    ${pkgs.llvmPackages.llvm}/bin/llvm-objcopy \
      --redefine-sym _main=_wawona_nvim_main "$MAIN_OBJ" "$WORKDIR/wawona_nvim_main.o"
    rm -f "$MAIN_OBJ"
    "$XCODE_CLANG" -c "$SRC_ROOT/wwn-neovim-eval-stubs.c" \
      -arch "''${IOS_ARCH:-arm64}" -isysroot "$SDKROOT" ''${APPLE_DEPLOYMENT_FLAG} -fPIC \
      -o "$WORKDIR/wwn-neovim-eval-stubs.o"
    ${pkgs.llvmPackages.llvm}/bin/llvm-ar rcs libwawona-neovim.a "$WORKDIR"/*.o
    ${pkgs.llvmPackages.llvm}/bin/llvm-nm --defined-only -g --format=posix \
      libwawona-neovim.a > "$WORKDIR/defined-symbols.txt"
    for symbol in _lua_newstate _luaL_newstate; do
      awk -v symbol="$symbol" '$1 == symbol { found = 1 } END { exit !found }' \
        "$WORKDIR/defined-symbols.txt" || {
          echo "required native PUC Lua definition missing: $symbol" >&2
          exit 1
        }
    done
    if ${pkgs.llvmPackages.llvm}/bin/llvm-nm libwawona-neovim.a 2>/dev/null | grep '_ExpandBufnames' | grep -q ' U ' \
      && ! ${pkgs.llvmPackages.llvm}/bin/llvm-nm libwawona-neovim.a 2>/dev/null | grep '_ExpandBufnames' | grep -qE ' [TW] '; then
      echo "buffer.c.o / _ExpandBufnames missing from libwawona-neovim.a" >&2
      exit 1
    fi
    rm -rf "$WORKDIR"
  '';
in
{
  inherit version neovimSrc applyAppleMobilePatches collectArchive;
  inherit cmakeExtraMac cmakeExtraAppleMobile depsCmakeExtraAppleMobile baseNative macNative;
  inherit hostCodegenPass iosCrossBuildPass;
}
