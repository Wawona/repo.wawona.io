#!/bin/bash

# Wawona Repository Setup Script
# Supports: iOS (NewTerm/Terminal) and Android (Termux)

set -e

echo "[*] Wawona Repository Setup"
echo "[!] APT for Sileo (jailbroken iOS, rootless/rootful) or Termux (sideloaded Android, not jailbreak). App Store and Play Wawona use wpm and /wasm/v1. Do not run this in a store binary."

# Detect OS
OS_TYPE=$(uname -o 2>/dev/null || echo "Unknown")
IS_ANDROID=false
if [ "$OS_TYPE" = "Android" ]; then
    IS_ANDROID=true
fi

# Determine Prefix and Source Path
REPO_URL="https://repo.wawona.io"
if [ "$IS_ANDROID" = true ]; then
    echo "[+] Detected Android (Termux)"
    SOURCE_FILE="$PREFIX/etc/apt/sources.list.d/wawona.list"
else
    echo "[+] Detected iOS/Darwin"
    # iOS typically uses /etc/apt/sources.list.d/ or similar
    if [ -d "/var/jb/etc/apt" ]; then
        SOURCE_FILE="/var/jb/etc/apt/sources.list.d/wawona.list"
    else
        SOURCE_FILE="/etc/apt/sources.list.d/wawona.list"
    fi
fi

echo "[+] Adding source: $REPO_URL"
echo "[+] Target file: $SOURCE_FILE"

# Prepare the universal trusted source line
LINE="deb [trusted=yes] $REPO_URL ./"

# Ensure directory exists and overwrite the file (cleanses legacy broken lines)
if [ "$IS_ANDROID" = true ]; then
    mkdir -p "$(dirname "$SOURCE_FILE")"
    echo "$LINE" > "$SOURCE_FILE"
    echo "[+] Repository updated in $SOURCE_FILE"
else
    # iOS - handle sudo
    DIR=$(dirname "$SOURCE_FILE")
    if [ "$(id -u)" -ne 0 ]; then
        sudo mkdir -p "$DIR"
        echo "$LINE" | sudo tee "$SOURCE_FILE" > /dev/null
        echo "[+] Repository updated in $SOURCE_FILE"
    else
        mkdir -p "$DIR"
        echo "$LINE" > "$SOURCE_FILE"
        echo "[+] Repository updated in $SOURCE_FILE"
    fi
fi

echo "[+] Repository added successfully!"
echo "[*] Running apt update..."

if [ "$IS_ANDROID" = true ]; then
    apt update
else
    if [ "$(id -u)" -ne 0 ]; then
        sudo apt update
    else
        apt update
    fi
fi

echo "[!] Done! You can now install Wawona packages using 'apt install <pkg>'"
