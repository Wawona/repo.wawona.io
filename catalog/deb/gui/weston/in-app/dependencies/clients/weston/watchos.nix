# watchOS: same in-process weston as iOS. Never force GL clients.
# allowGpu is false on watch (no Metal / ANGLE / OpenGLES). Forcing
# enableGlClients=true compiled clients_simple_egl into libweston-13.a and
# WawonaWatch then failed link on EGL/GL symbols. Honour the caller's
# enableGlClients (Wawona mobile-platform-deps sets false). Cited:
# wawona-platform-targets, wawona-relay-wasm.
args: import ./ios.nix args
