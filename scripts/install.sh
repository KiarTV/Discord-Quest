#!/usr/bin/env bash
# Discord Quest Game Mirror - macOS installer/launcher.
#
#   curl -fsSL https://raw.githubusercontent.com/KiarTV/Discord-Quest/master/scripts/install.sh -o install.sh && chmod +x install.sh && ./install.sh
#
# Makes sure PowerShell 7 (pwsh) is available - installing it via Homebrew if
# it isn't - then downloads and runs the actual tool (mirror.ps1). Re-running
# this script always re-downloads mirror.ps1, so it doubles as an updater.
# Any arguments are passed straight through to mirror.ps1, e.g.:
#   ./install.sh -GameName "Roblox"

set -euo pipefail

MIRROR_URL="https://raw.githubusercontent.com/KiarTV/Discord-Quest/master/mirror.ps1"
CACHE_DIR="$HOME/Library/Caches/quest-mirror"
MIRROR_SCRIPT="$CACHE_DIR/mirror.ps1"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This installer is for macOS. On Windows, run mirror.ps1 directly - see the README." >&2
    exit 1
fi

if ! command -v pwsh >/dev/null 2>&1; then
    echo "PowerShell (pwsh) not found - installing via Homebrew..."
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew is required to install pwsh automatically." >&2
        echo "Install it from https://brew.sh, then re-run this script." >&2
        exit 1
    fi
    brew install --cask powershell

    if ! command -v pwsh >/dev/null 2>&1; then
        echo "pwsh still isn't on PATH after installing - open a new terminal and try again." >&2
        exit 1
    fi
fi

mkdir -p "$CACHE_DIR"
echo "Fetching mirror.ps1..."
curl -fsSL "$MIRROR_URL" -o "$MIRROR_SCRIPT"

exec pwsh -NoProfile -File "$MIRROR_SCRIPT" "$@"
