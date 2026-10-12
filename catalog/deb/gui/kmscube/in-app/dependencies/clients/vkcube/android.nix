# Native krh/vkcube for Android — Wayland client over iland AHB dmabuf winsys.
{
  lib,
  pkgs,
  buildModule,
  androidToolchain ? (
    import "${toolchainSrc}/dependencies/toolchains/android.nix" {
      inherit lib pkgs;
    }
  ),
  toolchainSrc ? null,
  ...
}:

let
  iland = buildModule.buildForAndroid "iland" { };
  libwayland = buildModule.buildForAndroid "libwayland" { };
  waylandProtocols = pkgs.wayland-protocols;
in
pkgs.stdenv.mkDerivation {
  pname = "vkcube-android";
  version = "0.1.0-ffd5669";
  src = ../../../upstream/vkcube;
  dontConfigure = true;
  nativeBuildInputs = [ pkgs.wayland-scanner ];
  buildPhase = ''
    runHook preBuild
    cp ${../../../upstream/wwn_cube_hud.c} wwn_cube_hud.c
    cp ${../../../upstream/wwn_cube_hud.h} wwn_cube_hud.h
    CC="${androidToolchain.androidCC}"
    AR="${androidToolchain.androidAR}"

    XDG_XML="${waylandProtocols}/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
    wayland-scanner client-header "$XDG_XML" xdg-shell-client-protocol.h
    wayland-scanner private-code  "$XDG_XML" xdg-shell-protocol.c

    CFLAGS="-fPIC -O2 -std=c11 -I. -I${iland}/include \
      -I${pkgs.vulkan-headers}/include \
      -I${libwayland}/include -I${libwayland}/include/wayland"

    echo "CC libvkcube.a (Wayland)"
    "$CC" -c $CFLAGS -Dmain=vkcube_main main.c -o vkcube_main.o
    "$CC" -c $CFLAGS xdg-shell-protocol.c -o xdg-shell-protocol.o
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
    printf '%s\n' system swiftshader turnip \
      > "$out/nix-support/required-vulkan-registry-providers"
    cat > "$out/nix-support/vkcube-build-metadata.json" <<'EOF'
    {
      "upstream": "krh/vkcube",
      "revision": "ffd566971fac916fc90d33a442369d5717ceb2a9",
      "presentation": "wayland-ahb-dmabuf",
      "defaultVulkanProvider": "system",
      "fallbackVulkanProvider": "swiftshader",
      "compatibleVulkanProviders": ["system", "swiftshader", "turnip"],
      "translationLayers": []
    }
    EOF
  '';
  meta = with lib; {
    description = "Native in-process Vulkan cube over Wayland AHB dmabuf for Android";
    homepage = "https://github.com/krh/vkcube";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
