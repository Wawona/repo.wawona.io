# Canonical Weston client ids bundled/launchable in Wawona (Machines UI + native launchers).
{ lib }:
let
  demoClients = [
    "weston-flower"
    "weston-clickdot"
    "weston-smoke"
    "weston-eventdemo"
    "weston-resizor"
    "weston-cliptest"
    "weston-transformed"
    "weston-stacking"
    "weston-dnd"
    "weston-image"
    "weston-scaler"
    "weston-editor"
    "weston-constraints"
  ];
  coreClients = [
    "weston"
    "weston-terminal"
    "weston-simple-shm"
  ];
  optionalGlClients = [ "weston-simple-egl" ];
  hostClients = coreClients ++ demoClients ++ optionalGlClients;
in
{
  inherit demoClients coreClients optionalGlClients hostClients;

  inProcessClients = hostClients ++ [ "foot" "kmscube" ];
  macosBinaryClients = hostClients ++ [ "foot" "kmscube" ];

  verifyWestonPackageClients =
    weston:
    ''
      verify_weston_client() {
        local id="$1"
        local optional="$2"
        if [ -f "${weston}/bin/$id" ]; then
          echo "✓ $id"
          return 0
        fi
        if [ "$optional" = "1" ]; then
          echo "○ $id (optional, not built for this platform)"
          return 0
        fi
        echo "ERROR: missing required Weston client: ${weston}/bin/$id" >&2
        return 1
      }
      missing=0
      ${lib.concatMapStringsSep "\n" (id:
        if lib.elem id optionalGlClients then
          ''verify_weston_client "${id}" 1 || missing=1''
        else
          ''verify_weston_client "${id}" 0 || missing=1''
      ) hostClients}
      if [ "$missing" -ne 0 ]; then
        echo "Weston client bundle verification failed. Built clients:" >&2
        ls -la "${weston}/bin"/weston* 2>&1 || true
        exit 1
      fi
    '';
}
