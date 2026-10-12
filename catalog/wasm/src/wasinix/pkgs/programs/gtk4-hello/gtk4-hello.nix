# GTK4 "Hello, Wayland World!" linking wasinix libraries.gtk4 (toolkit).
# Execute under Relay with wawona_wayland_* host imports (Wasmer WASIX).
{
  lib,
  stdenv,
  toolchain,
  pkg-config,
  libraries,
}: let
  # Headers: multi-output .dev. glibconfig.h stays on .out (getLib).
  gtk4 = lib.getDev libraries.gtk4;
  gtk4Lib = lib.getLib libraries.gtk4;
  glib = lib.getDev libraries.glib;
  glibLib = lib.getLib libraries.glib;
  cairo = lib.getDev libraries.cairo;
  cairoLib = lib.getLib libraries.cairo;
  pango = lib.getDev libraries.pango;
  pangoLib = lib.getLib libraries.pango;
  gdkPixbuf = lib.getDev libraries.gdk-pixbuf;
  gdkPixbufLib = lib.getLib libraries.gdk-pixbuf;
  graphene = lib.getDev libraries.graphene;
  grapheneLib = lib.getLib libraries.graphene;
  wayland = lib.getDev libraries.wayland;
  waylandLib = lib.getLib libraries.wayland;
  libepoxy = lib.getDev libraries.libepoxy;
  libepoxyLib = lib.getLib libraries.libepoxy;
  libxkbcommon = lib.getDev libraries.libxkbcommon;
  libxkbcommonLib = lib.getLib libraries.libxkbcommon;
  harfbuzz = lib.getDev libraries.harfbuzz;
  harfbuzzLib = lib.getLib libraries.harfbuzz;
  fribidi = lib.getDev libraries.fribidi;
  fribidiLib = lib.getLib libraries.fribidi;
  fontconfig = lib.getDev libraries.fontconfig;
  fontconfigLib = lib.getLib libraries.fontconfig;
  pixman = lib.getDev libraries.pixman;
  pixmanLib = lib.getLib libraries.pixman;
  pcre2 = lib.getDev libraries.pcre2;
  pcre2Lib = lib.getLib libraries.pcre2;
  libffi = lib.getDev libraries.libffi;
  libffiLib = lib.getLib libraries.libffi;
  expat = lib.getDev libraries.expat;
  expatLib = lib.getLib libraries.expat;
in
  stdenv.mkDerivation {
    pname = "gtk4-hello";
    version = "0.1.0";

    dontUnpack = true;

    nativeBuildInputs = [
      toolchain.wasixcc
      pkg-config
    ];

    buildInputs = [
      libraries.gtk4
      libraries.glib
      libraries.cairo
      libraries.pango
      libraries.gdk-pixbuf
      libraries.graphene
      libraries.libxkbcommon
      libraries.wayland
      libraries.libepoxy
      libraries.harfbuzz
      libraries.fribidi
      libraries.fontconfig
      libraries.pixman
      libraries.pcre2
      libraries.libffi
      libraries.expat
      libraries.wasixWawonaWayland
      libraries.wasixCompat
    ];

    buildPhase = ''
      runHook preBuild
      ${toolchain.toolchainEnv}
      ${toolchain.ccEnv}

      export PKG_CONFIG_PATH="$(find ${gtk4} ${glib} ${cairo} ${pango} ${gdkPixbuf} ${graphene} ${wayland} ${libepoxy} -type d -name pkgconfig 2>/dev/null | tr '\n' ':' )''${PKG_CONFIG_PATH:-}"

      cflags=$(pkg-config --cflags gtk4 glib-2.0 2>/dev/null || echo "")
      # Fallback include roots. gtk/gtk.h under include/gtk-4.0/; glibconfig.h on out.
      cflags="$cflags -I${gtk4}/include -I${gtk4}/include/gtk-4.0"
      cflags="$cflags -I${glib}/include -I${glib}/include/glib-2.0"
      cflags="$cflags -I${glib}/lib/glib-2.0/include -I${glibLib}/lib/glib-2.0/include"
      cflags="$cflags -I${glib}/include/gio-unix-2.0"
      cflags="$cflags -I${cairo}/include -I${cairo}/include/cairo"
      cflags="$cflags -I${pango}/include -I${pango}/include/pango-1.0"
      cflags="$cflags -I${gdkPixbuf}/include -I${gdkPixbuf}/include/gdk-pixbuf-2.0"
      cflags="$cflags -I${graphene}/include -I${graphene}/include/graphene-1.0"
      cflags="$cflags -I${graphene}/lib/graphene-1.0/include -I${grapheneLib}/lib/graphene-1.0/include"
      cflags="$cflags -I${wayland}/include"
      cflags="$cflags -I${libepoxy}/include"
      cflags="$cflags -I${libxkbcommon}/include"
      cflags="$cflags -I${harfbuzz}/include -I${harfbuzz}/include/harfbuzz"
      cflags="$cflags -I${fribidi}/include -I${fribidi}/include/fribidi"
      cflags="$cflags -I${fontconfig}/include"
      cflags="$cflags -I${pixman}/include -I${pixman}/include/pixman-1"
      cflags="$cflags -I${pcre2}/include"
      cflags="$cflags -I${libffi}/include"
      cflags="$cflags -I${expat}/include"

      echo "gtk4-hello probe:" >&2
      ls -la ${gtk4}/include/gtk-4.0/gtk/gtk.h >&2
      ls -la ${glibLib}/lib/glib-2.0/include/glibconfig.h >&2
      ls -la ${gtk4Lib}/lib/libgtk-4.a >&2

      $CC -O2 $cflags ${./main.c} -o gtk4-hello.wasm \
        -L${gtk4Lib}/lib -lgtk-4 \
        -L${glibLib}/lib -lgio-2.0 -lgobject-2.0 -lglib-2.0 \
        -L${cairoLib}/lib -lcairo \
        -L${pangoLib}/lib -lpangocairo-1.0 -lpango-1.0 \
        -L${gdkPixbufLib}/lib -lgdk_pixbuf-2.0 \
        -L${grapheneLib}/lib -lgraphene-1.0 \
        -L${libxkbcommonLib}/lib -lxkbcommon \
        -L${waylandLib}/lib -lwayland-client -lwayland-cursor -lwayland-egl \
        -L${libepoxyLib}/lib -lepoxy \
        -L${harfbuzzLib}/lib -lharfbuzz \
        -L${fribidiLib}/lib -lfribidi \
        -L${fontconfigLib}/lib -lfontconfig \
        -L${pixmanLib}/lib -lpixman-1 \
        -L${pcre2Lib}/lib -lpcre2-8 \
        -L${libffiLib}/lib -lffi \
        -L${expatLib}/lib -lexpat \
        -L${libraries.wasixWawonaWayland}/lib -lwawona-wayland \
        -L${libraries.wasixCompat}/lib -lwasix-compat \
        -Wl,--wrap=connect -Wl,--wrap=sendmsg -Wl,--wrap=recvmsg -Wl,--wrap=poll -Wl,--wrap=close \
        -Wl,--allow-undefined \
        -lc++ -lc++abi -lunwind
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      cp gtk4-hello.wasm $out/bin/gtk4-hello.wasm
      runHook postInstall
    '';

    meta = {
      description = "Hello, Wayland World! GTK4 demo for WASIX (links libraries.gtk4)";
      homepage = "https://github.com/Wawona/wasinix/tree/development/pkgs/programs/gtk4-hello";
      license = lib.licenses.mit;
    };
  }
