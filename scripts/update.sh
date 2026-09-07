#!/usr/bin/env bash
set -e

# Path setup
SCRIPT_DIR=$(dirname "$(realpath "$0")")
ROOT=$(dirname "$SCRIPT_DIR")
REPO_ROOT="$ROOT"
ARCH_IOS_64="iphoneos-arm64"
ARCH_IOS_64E="iphoneos-arm64e"
ARCH_ANDROID="aarch64"
ALL_ARCHS="$ARCH_IOS_64 $ARCH_IOS_64E $ARCH_ANDROID"

# Helpers
get_size() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1"; }
sed_i() { if sed --version 2>/dev/null | grep -q "GNU"; then sed -i "$@"; else sed -i '' "$@"; fi; }

# RootHide Patching (omitted for brevity, keep existing function if possible)
patch_roothide() {
    local input="$1"
    local out_dir="$2"
    local filename=$(basename "$input")
    if [[ "$filename" == *"~roothide"* ]]; then return 0; fi
    local pkg_name="${filename%%_*}"
    local pkg_ver=$(echo "$filename" | cut -d'_' -f2)
    local output_filename="${pkg_name}_${pkg_ver}~roothide_iphoneos-arm64e.deb"
    local output_path="$out_dir/$output_filename"
    if [ -f "$output_path" ]; then return 0; fi
    echo "Patching $filename for RootHide..."
    local tmp=$(mktemp -d)
    dpkg-deb -R "$input" "$tmp"
    sed_i "s/^Architecture: .*/Architecture: $ARCH_IOS_64E/" "$tmp/DEBIAN/control"
    sed_i "s/^Version: .*/Version: ${pkg_ver}~roothide/" "$tmp/DEBIAN/control"
    if ! grep -q "RootHide:" "$tmp/DEBIAN/control"; then echo "RootHide: true" >> "$tmp/DEBIAN/control"; fi
    if ! grep -q "Tag:" "$tmp/DEBIAN/control"; then echo "Tag: role::tweak, roothide::compatible" >> "$tmp/DEBIAN/control"; fi
    dpkg-deb -b "$tmp" "$output_path" > /dev/null
    rm -rf "$tmp"
}

update_repo() {
    echo "Updating unified repository index at $REPO_ROOT..."
    
    cd "$REPO_ROOT"
    mkdir -p "debs"
    
    # Scan ALL debs for universal flat repo
    dpkg-scanpackages -m "debs" /dev/null 2>/dev/null > "Packages"
    sed_i 's/^Roothide: /RootHide: /g' "Packages"
    gzip --no-name -c9 "Packages" > "Packages.gz"
    
    # Unified Release file with MD5 and SHA256
    cat > "Release" <<EOF
Origin: Wawona
Label: Wawona
Suite: stable
Codename: stable
Architectures: $ALL_ARCHS
Components: main
Description: Wawona System Utilities (iOS & Android)
Date: $(date -R)
MD5Sum:
 $(md5sum "Packages" | cut -d' ' -f1) $(get_size "Packages") Packages
 $(md5sum "Packages.gz" | cut -d' ' -f1) $(get_size "Packages.gz") Packages.gz
SHA256:
 $(shasum -a 256 "Packages" | cut -d' ' -f1) $(get_size "Packages") Packages
 $(shasum -a 256 "Packages.gz" | cut -d' ' -f1) $(get_size "Packages.gz") Packages.gz
EOF
    cp "Release" "Releases"
}

if [ "${WAWONA_BUILD_PACKAGES:-0}" = 1 ]; then
    echo "Step 1: Building multi-platform aggregate (WAWONA_BUILD_PACKAGES=1)..."
    nix build .#ios --out-link "$ROOT/result-ios" || echo "iOS build skipped"
    nix build .#android --out-link "$ROOT/result-android" || echo "Android build skipped"
else
    echo "Step 1: Skipping nix aggregate. Set WAWONA_BUILD_PACKAGES=1 to build .#ios / .#android."
fi

echo "Step 2: Collecting binaries..."
mkdir -p "$REPO_ROOT/debs"
if [ -L "$ROOT/result-ios" ]; then find "$ROOT/result-ios" -name "*.deb" -exec cp -vu {} "$REPO_ROOT/debs/" \; ; fi
if [ -L "$ROOT/result-android" ]; then find "$ROOT/result-android" -name "*.deb" -exec cp -vu {} "$REPO_ROOT/debs/" \; ; fi

echo "Step 3: Processing iOS RootHide..."
mkdir -p "$REPO_ROOT/roothide"
for deb in "$REPO_ROOT/debs"/*.deb; do 
    [[ "$deb" == *"~roothide"* ]] && continue
    # Only patch if it's an iOS architecture
    if dpkg-deb -f "$deb" Architecture | grep -q "iphoneos"; then
        patch_roothide "$deb" "$REPO_ROOT/roothide"
    fi
done
cp "$REPO_ROOT/roothide"/*.deb "$REPO_ROOT/debs/" 2>/dev/null || true

echo "Step 4: Generating Unified Index..."
update_repo

echo "Step 5: Final Cleanup..."
if [ -d "$ROOT/repo" ]; then rm -rf "$ROOT/repo" ; fi
if [ -d "$ROOT/ios" ]; then rm -rf "$ROOT/ios" ; fi
if [ -d "$ROOT/android" ]; then rm -rf "$ROOT/android" ; fi
echo "Wawona Repository Unified Successfully."

# Clean up legacy repo directory if it exists
if [ -d "$ROOT/repo" ]; then rm -rf "$ROOT/repo" ; fi

cd "$ROOT"
if [ -d ".git" ]; then
    git add Packages Packages.gz Release debs/
fi
echo "Wawona Repository Updated Successfully."
