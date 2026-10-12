# Staged niri source for the Wawona port: upstream v26.04 plus the Wawona
# nested-backend patch (niri as a Wayland client of the Wawona compositor).
#
# The patch:
# - adds src/backend/nested/ (Wayland-client backend: xdg_toplevel output,
#   GLES over EGL_KHR_platform_wayland, host-seat input translation),
# - gates the Linux-only stacks (DRM/KMS tty backend, winit backend, libinput,
#   udev/libseat, pipewire, drm-lease, gamma) behind cfg(target_os = "linux"),
# - adds the niri_main C ABI entry (src/c_api.rs) + staticlib crate-type so
#   mobile targets can host niri in-process (App Store posture),
# - keeps desktop-Linux builds byte-for-byte functional (all gates are
#   cfg(target_os = "linux") supersets of upstream behavior).
{ pkgs }:

pkgs.applyPatches {
  name = "niri-src-wawona-v26.04";
  src = pkgs.fetchFromGitHub {
    owner = "YaLTeR";
    repo = "niri";
    rev = "v26.04";
    hash = "sha256-ehSMsSpE+0k8r+2Vseu8kangsYxToZv3vinynsDp9zs=";
  };
  patches = [
    ./wawona-nested-port.patch
    ./wawona-spawn-mobile.patch
    # Keep panics inside niri_main from aborting the host Wawona process
    # (extern "C" + panic_cannot_unwind → SIGABRT on iOS Simulator).
    ./wawona-niri-main-catch-unwind.patch
    # iOS/tvOS/watchOS/visionOS/Android: ANGLE has no wl_egl_window. Nested
    # niri uses iland's Wayland-EGL on every GPU target; watchOS (blocked)
    # and tvOS (GPU still planned) stay on offscreen GLES + wl_shm.
    ./wawona-nested-apple-shm.patch
    # ANGLE on Apple/Android often rejects 10-bit GLES 3.0 configs. Try
    # 8-bit GLES 3.0 first, then GLES 2.0, and keep the smithay error in the
    # anyhow chain so niri_main can print it.
    ./wawona-nested-egl-context.patch
    # Nested inside pixman weston (no zwp_linux_dmabuf_v1): present via wl_shm
    # so the xdg_toplevel actually maps. Iland EGL winsys is for Wawona's own
    # compositor, not for an inner weston. Also maximize so a phone-sized
    # weston is not asked for 1280x800.
    ./wawona-nested-shm-without-host-dmabuf.patch
    # iOS / WWN_NIRI_SHM: do not pick PLATFORM_WAYLAND_KHR. That path
    # selected EGL then Nested::new died before SHM present. Use ANGLE
    # Metal with a null native display, then offscreen + wl_shm.
    ./wawona-nested-ios-angle-metal-shm.patch
    # iOS SHM: iland does not wrap PLATFORM_ANGLE_ANGLE. Use GBM so
    # eglInitialize hits ANGLE DEFAULT, and print the EGL error chain.
    ./wawona-nested-ios-gbm-shm.patch
    # macOS/Android/iOS: skip xwayland-satellite (not bundled; no X11 session).
    ./wawona-xwayland-satellite-off.patch
    # macOS Mode B: compile the DRM/KMS tty backend (NIRI_BACKEND=tty) against
    # iland userspace KMS. iOS/Android stay nested-only. winit stays Linux-only.
    ./wawona-macos-drm-tty.patch
    # Mode B: open DRM via libc (iland hooks) instead of rustix stat(2).
    ./wawona-macos-drm-open.patch
  ];
}
