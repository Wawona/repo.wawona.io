# krh/vkcube as a Wayland client over iland's IOSurface dmabuf winsys +
# MoltenVK. Apple mobile archive (iOS / iPadOS / visionOS / tvOS). watchOS
# has no registry variant: no Metal, Vulkan stays blocked.
{
  lib,
  pkgs,
  buildModule,
  simulator ? false,
  iosToolchain,
  xcodeUtils ? iosToolchain,
  toolchainSrc ? null,
  ...
}:

let
  iland = buildModule.buildForIOS "iland" { inherit simulator; };
  libwayland = buildModule.buildForIOS "libwayland" { inherit simulator; };
  mobile = (import "${toolchainSrc}/dependencies/toolchains/apple-mobile-platform.nix") {
    inherit iosToolchain simulator;
  };
  sdkPlatform = mobile.sdkPlatform;
  minVerFlag = mobile.minVerFlag;
  waylandProtocols = pkgs.wayland-protocols;
in
pkgs.stdenv.mkDerivation {
  pname = "vkcube-apple-mobile";
  version = "0.1.0-ffd5669";

  src = ../../../upstream/vkcube;

  __noChroot = true;
  dontConfigure = true;

  nativeBuildInputs = [ pkgs.wayland-scanner ];

  buildPhase = ''
    runHook preBuild

    cp ${../../../upstream/wwn_cube_hud.c} wwn_cube_hud.c
    cp ${../../../upstream/wwn_cube_hud.h} wwn_cube_hud.h

    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      [ -n "$XCODE_APP" ] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    fi
    export SDKROOT="$DEVELOPER_DIR/Platforms/${sdkPlatform}.platform/Developer/SDKs/${sdkPlatform}.sdk"
    CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"

    XDG_XML="${waylandProtocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
    wayland-scanner client-header "$XDG_XML" xdg-shell-client-protocol.h
    wayland-scanner private-code  "$XDG_XML" xdg-shell-protocol.c

    CFLAGS="-arch arm64 -isysroot $SDKROOT ${minVerFlag} -fPIC -O2 -std=c11 \
      -I. -I${iland}/include -I${pkgs.vulkan-headers}/include \
      -I${libwayland}/include -I${libwayland}/include/wayland"

    echo "CC libvkcube.a (native in-process vkcube_main, Wayland)"
    "$CLANG" -c $CFLAGS -Dmain=vkcube_main main.c -o vkcube_main.o
    "$CLANG" -c $CFLAGS xdg-shell-protocol.c -o xdg-shell-protocol.o
    "$AR" rcs libvkcube.a vkcube_main.o xdg-shell-protocol.o

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p "$out/lib" "$out/include" "$out/nix-support"
    install -m644 libvkcube.a "$out/lib/"
    cat > "$out/include/vkcube.h" <<'EOF'
    #ifndef WAWONA_VKCUBE_H
    #define WAWONA_VKCUBE_H
    int vkcube_main(int argc, char *argv[]);
    #endif
    EOF
    echo "${iland}" > "$out/nix-support/iland-path"
    echo "${libwayland}" > "$out/nix-support/libwayland-path"
    echo moltenvk > "$out/nix-support/required-vulkan-registry-providers"
    cat > "$out/nix-support/vkcube-build-metadata.json" <<'EOF'
    {
      "upstream": "krh/vkcube",
      "revision": "ffd566971fac916fc90d33a442369d5717ceb2a9",
      "presentation": "wayland-iosurface-dmabuf",
      "vulkanProvider": "moltenvk-static",
      "translationLayers": []
    }
    EOF
  '';

  meta = with lib; {
    description = "Native in-process Vulkan cube over Wayland IOSurface dmabuf for Apple mobile";
    homepage = "https://github.com/krh/vkcube";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
