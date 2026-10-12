# Native krh/vkcube for macOS. Two binaries, two presentation paths:
#   vkcube     Wayland client over iland IOSurface dmabuf (nested / Mode A)
#   vkcube-kms iland KMS/GBM own-display (Mode B Classic, or Display Backend=DRM)
# Resolves Vulkan against MoltenVK or KosmicKrisp via WWN_VULKAN_LIBRARY.
{
  lib,
  pkgs,
  buildModule,
  xcodeUtils,
  ...
}:

let
  iland = buildModule.buildForMacOS "iland" { };
  libwayland = buildModule.buildForMacOS "libwayland" { };
  waylandProtocols = pkgs.wayland-protocols;
in
pkgs.stdenv.mkDerivation {
  pname = "vkcube-macos";
  version = "0.1.0-ffd5669";

  src = ../../../upstream/vkcube;

  __noChroot = true;
  dontConfigure = true;

  nativeBuildInputs = [ pkgs.wayland-scanner ];

  buildPhase = ''
    runHook preBuild

    cp ${../../../upstream/wwn_cube_hud.c} wwn_cube_hud.c
    cp ${../../../upstream/wwn_cube_hud.h} wwn_cube_hud.h

    unset DEVELOPER_DIR
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    test -d "$MACOS_SDK"

    CLANG="${pkgs.clang}/bin/clang"

    XDG_XML="${waylandProtocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
    wayland-scanner client-header "$XDG_XML" xdg-shell-client-protocol.h
    wayland-scanner private-code  "$XDG_XML" xdg-shell-protocol.c

    CFLAGS="-isysroot $MACOS_SDK -mmacosx-version-min=12.0 -fPIC -O2 -std=c11 \
      -I. -I${iland}/include -I${pkgs.vulkan-headers}/include \
      -I${libwayland}/include"

    FRAMEWORKS="-framework IOSurface -framework Foundation -framework CoreFoundation \
      -framework CoreGraphics -framework QuartzCore -framework Metal -framework Accelerate"
    # Winsys (dmabuf post) lives in libiland_wayland_egl; core has no Wayland.
    # Optional WSI archive is not required for this client — it calls the
    # winsys present_pixels helper directly.
    LIBS="-L${iland}/lib -liland_wayland_egl -liland_userland \
      -L${libwayland}/lib -lwayland-client"

    echo "CC libvkcube.a (native in-process vkcube_main, Wayland)"
    "$CLANG" -c $CFLAGS -Dmain=vkcube_main main.c -o vkcube_main.o
    "$CLANG" -c $CFLAGS xdg-shell-protocol.c -o xdg-shell-protocol.o
    ar rcs libvkcube.a vkcube_main.o xdg-shell-protocol.o

    echo "CC vkcube (standalone Wayland binary)"
    "$CLANG" $CFLAGS main.c xdg-shell-protocol.c $LIBS $FRAMEWORKS \
      -Wl,-rpath,${libwayland}/lib -o vkcube_bin

    # Own-display KMS/GBM path (Mode B Classic, or Mode A Display Backend=DRM).
    # Separate binary: do not merge with the Wayland client. Nested Machines
    # Start still launches bin/vkcube against WAYLAND_DISPLAY.
    # Force-include the store-safe /dev/dri/cardN redirect (same as kmscube).
    # Raw open("/dev/dri/card0") is ENOENT on Apple; Mode B overlay children
    # of igettyd do not get a Dobby open() hook.
    echo "CC vkcube-kms (standalone KMS/GBM binary)"
    "$CLANG" $CFLAGS -include ${iland}/include/iland_drm_open_compat.h \
      vkcube_kms.c -lm \
      -L${iland}/lib -liland_userland $FRAMEWORKS -o vkcube_kms_bin

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p "$out/bin" "$out/lib" "$out/include" "$out/nix-support"
    install -m755 vkcube_bin "$out/bin/vkcube"
    install -m755 vkcube_kms_bin "$out/bin/vkcube-kms"
    install -m644 libvkcube.a "$out/lib/"
    cat > "$out/include/vkcube.h" <<'EOF'
#ifndef WAWONA_VKCUBE_H
#define WAWONA_VKCUBE_H
int vkcube_main(int argc, char *argv[]);
#endif
EOF
    echo "${iland}" > "$out/nix-support/iland-path"
    echo "${libwayland}" > "$out/nix-support/libwayland-path"
    printf '%s\n' moltenvk kosmickrisp \
      > "$out/nix-support/required-vulkan-registry-providers"
    cat > "$out/nix-support/vkcube-build-metadata.json" <<'EOF'
    {
      "upstream": "krh/vkcube",
      "revision": "ffd566971fac916fc90d33a442369d5717ceb2a9",
      "presentation": "wayland-iosurface-dmabuf",
      "kmsBinary": "vkcube-kms",
      "defaultVulkanProvider": "moltenvk",
      "compatibleVulkanProviders": ["moltenvk", "kosmickrisp"],
      "translationLayers": []
    }
    EOF
  '';

  meta = with lib; {
    description = "Native Vulkan cube: Wayland (vkcube) and iland KMS/GBM (vkcube-kms) for macOS";
    homepage = "https://github.com/krh/vkcube";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
