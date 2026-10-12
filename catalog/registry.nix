# In-app registry keys. Same paths the old wwn-* flakes exported.
# Deb recipes do not use these files. Wawona merges this one fragment.
{ withPlatformVariants }:
let
  weston = ./deb/gui/weston/in-app;
  niri = ./deb/gui/niri/in-app;
  foot = ./deb/gui/foot/in-app;
  kmscube = ./deb/gui/kmscube/in-app;
  fastfetch = ./deb/cli/fastfetch/in-app;
  phoon = ./deb/cli/phoon/in-app;
  neovim = ./deb/cli/neovim/in-app;
  westonDir = weston + "/dependencies/clients/weston";
  shmDir = weston + "/dependencies/libs/weston-simple-shm";
  simpleEglDir = weston + "/dependencies/clients/weston-simple-egl";
  kmscubeDir = kmscube + "/dependencies/clients/kmscube";
  gbmDir = kmscube + "/dependencies/clients/gbm-es2-demo";
  niriDir = niri + "/dependencies/niri";
  fuzzelDir = niri + "/dependencies/fuzzel";
  footDir = foot + "/dependencies/clients/foot";
  ffDir = fastfetch + "/dependencies/clients/fastfetch";
  phDir = phoon + "/dependencies/libs/phoon";
  neovimDir = neovim + "/dependencies/libs/neovim";
in
{
  weston = withPlatformVariants {
    android = westonDir + "/android.nix";
    wearos = westonDir + "/wearos.nix";
    ios = westonDir + "/ios.nix";
    tvos = westonDir + "/tvos.nix";
    ipados = westonDir + "/ios.nix";
    visionos = westonDir + "/visionos.nix";
    watchos = westonDir + "/watchos.nix";
    macos = westonDir + "/macos-drm-shared.nix";
  };
  weston-compositor = withPlatformVariants {
    android = westonDir + "/compositor-android.nix";
    ios = westonDir + "/compositor-ios.nix";
    tvos = westonDir + "/compositor-tvos.nix";
    ipados = westonDir + "/compositor-ios.nix";
    visionos = westonDir + "/compositor-visionos.nix";
    watchos = westonDir + "/compositor-watchos.nix";
    macos = westonDir + "/compositor-macos-drm.nix";
  };
  weston-compositor-drm = withPlatformVariants {
    android = westonDir + "/compositor-android-drm.nix";
    ios = westonDir + "/compositor-ios-drm.nix";
    tvos = null;
    ipados = westonDir + "/compositor-ios-drm.nix";
    visionos = null;
    watchos = null;
    macos = westonDir + "/compositor-macos-drm.nix";
  };
  weston-compositor-gl = withPlatformVariants {
    android = westonDir + "/compositor-android-gl.nix";
    wearos = null;
    ios = null;
    tvos = null;
    ipados = null;
    visionos = null;
    watchos = null;
    macos = westonDir + "/compositor-macos-drm.nix";
  };
  weston-simple-egl = withPlatformVariants {
    android = null;
    ios = null;
    tvos = null;
    ipados = null;
    visionos = null;
    watchos = null;
    macos = simpleEglDir + "/macos.nix";
  };
  weston-simple-shm = withPlatformVariants {
    android = shmDir + "/android.nix";
    ios = shmDir + "/ios.nix";
    tvos = shmDir + "/tvos.nix";
    ipados = shmDir + "/ios.nix";
    visionos = shmDir + "/visionos.nix";
    watchos = shmDir + "/watchos.nix";
    macos = shmDir + "/macos.nix";
  };
  kmscube = withPlatformVariants {
    android = kmscubeDir + "/android.nix";
    wearos = kmscubeDir + "/wearos.nix";
    ios = kmscubeDir + "/ios.nix";
    tvos = kmscubeDir + "/tvos.nix";
    ipados = kmscubeDir + "/ipados.nix";
    visionos = kmscubeDir + "/visionos.nix";
    watchos = kmscubeDir + "/watchos.nix";
    macos = kmscubeDir + "/macos.nix";
    linux = kmscubeDir + "/linux.nix";
  };
  "gbm-es2-demo" = withPlatformVariants {
    android = gbmDir + "/android.nix";
    wearos = gbmDir + "/wearos.nix";
    ios = gbmDir + "/ios.nix";
    tvos = gbmDir + "/tvos.nix";
    ipados = gbmDir + "/ipados.nix";
    visionos = gbmDir + "/visionos.nix";
    watchos = gbmDir + "/watchos.nix";
    macos = gbmDir + "/macos.nix";
    linux = null;
  };
  vkcube = withPlatformVariants {
    android = kmscube + "/dependencies/clients/vkcube/android.nix";
    wearos = kmscube + "/dependencies/clients/vkcube/wearos.nix";
    ios = kmscube + "/dependencies/clients/vkcube/ios.nix";
    ipados = kmscube + "/dependencies/clients/vkcube/ipados.nix";
    visionos = kmscube + "/dependencies/clients/vkcube/visionos.nix";
    macos = kmscube + "/dependencies/clients/vkcube/macos.nix";
    tvos = kmscube + "/dependencies/clients/vkcube/tvos.nix";
    watchos = null;
    linux = null;
  };
  "opengl-cube" = withPlatformVariants {
    android = kmscube + "/dependencies/clients/opengl-cube/android.nix";
    wearos = kmscube + "/dependencies/clients/opengl-cube/wearos.nix";
    ios = kmscube + "/dependencies/clients/opengl-cube/ios.nix";
    ipados = kmscube + "/dependencies/clients/opengl-cube/ipados.nix";
    visionos = kmscube + "/dependencies/clients/opengl-cube/visionos.nix";
    macos = kmscube + "/dependencies/clients/opengl-cube/macos.nix";
    tvos = kmscube + "/dependencies/clients/opengl-cube/ios.nix";
    watchos = null;
    linux = null;
  };
  "iland-gl-clients" = withPlatformVariants {
    android = kmscubeDir + "/android.nix";
    wearos = kmscubeDir + "/wearos.nix";
    ios = kmscubeDir + "/ios.nix";
    tvos = kmscubeDir + "/tvos.nix";
    ipados = kmscubeDir + "/ipados.nix";
    visionos = kmscubeDir + "/visionos.nix";
    watchos = kmscubeDir + "/watchos.nix";
    macos = kmscubeDir + "/macos.nix";
    linux = null;
  };
  niri = withPlatformVariants {
    android = niriDir + "/android.nix";
    wearos = niriDir + "/android.nix";
    ios = niriDir + "/ios.nix";
    tvos = niriDir + "/ios.nix";
    ipados = niriDir + "/ios.nix";
    visionos = niriDir + "/ios.nix";
    watchos = niriDir + "/ios.nix";
    macos = niriDir + "/macos.nix";
  };
  fuzzel = withPlatformVariants {
    android = fuzzelDir + "/android.nix";
    wearos = fuzzelDir + "/stub.nix";
    ios = fuzzelDir + "/ios.nix";
    tvos = fuzzelDir + "/ios.nix";
    ipados = fuzzelDir + "/ios.nix";
    visionos = fuzzelDir + "/ios.nix";
    watchos = fuzzelDir + "/stub.nix";
    macos = fuzzelDir + "/macos.nix";
  };
  foot = withPlatformVariants {
    android = footDir + "/android.nix";
    wearos = footDir + "/wearos.nix";
    ios = footDir + "/ios.nix";
    tvos = footDir + "/tvos.nix";
    ipados = footDir + "/ipados.nix";
    visionos = footDir + "/visionos.nix";
    watchos = footDir + "/watchos.nix";
    macos = footDir + "/macos.nix";
  };
  fastfetch = withPlatformVariants {
    android = ffDir + "/android.nix";
    wearos = ffDir + "/wearos.nix";
    ios = ffDir + "/ios.nix";
    tvos = ffDir + "/tvos.nix";
    ipados = ffDir + "/ipados.nix";
    visionos = ffDir + "/visionos.nix";
    watchos = ffDir + "/watchos.nix";
    macos = ffDir + "/macos.nix";
    linux = ffDir + "/linux.nix";
  };
  phoon = withPlatformVariants {
    android = phDir + "/android.nix";
    wearos = phDir + "/wearos.nix";
    ios = phDir + "/ios.nix";
    tvos = phDir + "/tvos.nix";
    ipados = phDir + "/ipados.nix";
    visionos = phDir + "/visionos.nix";
    watchos = phDir + "/watchos.nix";
    macos = phDir + "/macos.nix";
    linux = phDir + "/linux.nix";
  };
  neovim = withPlatformVariants {
    android = neovimDir + "/android.nix";
    wearos = neovimDir + "/wearos.nix";
    ios = neovimDir + "/ios.nix";
    tvos = neovimDir + "/tvos.nix";
    ipados = neovimDir + "/ipados.nix";
    visionos = neovimDir + "/visionos.nix";
    watchos = neovimDir + "/watchos.nix";
    macos = neovimDir + "/macos.nix";
    linux = neovimDir + "/linux.nix";
  };
}
