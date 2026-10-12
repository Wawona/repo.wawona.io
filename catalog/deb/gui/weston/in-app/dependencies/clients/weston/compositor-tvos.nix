# tvOS: same in-process compositor as iOS. enableIlandDrm comes from
# Wawona (allowGpu). Cited: Wawona/docs/wwn-repo-dag.md.
# Re-export so toolchain functionArgs sees enableIlandDrm.
import ./compositor-apple-mobile.nix
