# Re-export so toolchain functionArgs sees enableIlandDrm.
# A unary `args: import … args` has empty functionArgs; callPackageFiltered then
# intersects weston/ios.nix (toytoolkit) and drops enableIlandDrm.
import ./compositor-apple-mobile.nix
