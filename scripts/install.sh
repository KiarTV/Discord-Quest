#!/usr/bin/env bash
# Discord Quest Game Mirror - macOS installer/launcher.
#
#   curl -fsSL https://raw.githubusercontent.com/KiarTV/Discord-Quest/master/scripts/install.sh | bash
#
# Makes sure PowerShell 7 (pwsh) is available - installing it via Homebrew if
# it isn't - then downloads and runs the actual tool (mirror.ps1). Re-running
# this always re-downloads mirror.ps1, so it doubles as an updater. Arguments
# pass straight through to mirror.ps1 via `bash -s -- <args>`, e.g.:
#   curl -fsSL .../install.sh | bash -s -- -GameName "Roblox"
#
# All status/log output below goes to stderr, on purpose: this script is
# meant to be piped straight into `bash`, but if someone instead pastes it
# wrapped in backticks or $(...) (easy to do by accident), stdout gets
# captured and re-run as a command. Keeping stdout empty until the final
# `exec pwsh` means that mistake fails quietly instead of surfacing a
# second, misleading "command not found" error on top of the real one.

set -euo pipefail

MIRROR_URL="https://raw.githubusercontent.com/KiarTV/Discord-Quest/master/mirror.ps1"
CACHE_DIR="$HOME/Library/Caches/quest-mirror"
MIRROR_SCRIPT="$CACHE_DIR/mirror.ps1"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This installer is for macOS. On Windows, run mirror.ps1 directly - see the README." >&2
    exit 1
fi

if ! command -v pwsh >/dev/null 2>&1; then
    echo "PowerShell (pwsh) not found - installing via Homebrew..." >&2
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
echo "Fetching mirror.ps1..." >&2
curl -fsSL "$MIRROR_URL" -o "$MIRROR_SCRIPT"

exec pwsh -NoProfile -File "$MIRROR_SCRIPT" "$@"
