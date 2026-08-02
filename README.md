# Discord Quest Game Mirror

Type a game's name, get a process running with that game's exact executable
name - so Discord's Quest detection sees it as "running" - without
downloading or installing anything.

Works on **Windows** and **macOS**.

## How it works

Discord Quests check whether a process with a specific executable filename is
running - nothing more. This tool:

1. Looks up the game in Discord's own public list of detectable applications
   to find the exact executable name it checks for on your platform.
2. If the raw name you typed doesn't match well, it cross-checks Steam's
   store search to canonicalize the name (e.g. "gta 5" -> "Grand Theft Auto V")
   and retries.
3. Copies a harmless built-in system binary to a working folder, renamed to
   match, and runs it for ~17.5 minutes - a few minutes longer than the 15
   minutes most Quests require.

This only affects what your own local Discord client detects. It doesn't
touch your account, other users, or any network service.

On macOS, this is a best-effort implementation - Discord's macOS Quest
detection hasn't been confirmed against real Quests the way the Windows path
has. If it doesn't work for you, please open an issue with what you tried.

## Usage

### Windows

No download needed - run directly from GitHub in PowerShell:

```powershell
irm https://raw.githubusercontent.com/KiarTV/Discord-Quest/master/mirror.ps1 | iex
```

### macOS

No download needed - run directly from GitHub in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/KiarTV/Discord-Quest/master/scripts/install.sh | bash
```

Nothing to install beforehand - no Homebrew, no admin password needed. If
PowerShell isn't already on your Mac, the installer downloads it
automatically the first time you run this and reuses it after that.

If you already have PowerShell (`pwsh`) installed and prefer the same
one-liner style as Windows, that also works from inside `pwsh`:

```powershell
irm https://raw.githubusercontent.com/KiarTV/Discord-Quest/master/mirror.ps1 | iex
```

### The prompt

Either platform lands you in a small prompt (`quest-mirror >`). Type a game
name to queue a mirror for it - each one launches as its own process, so you
can queue several games in parallel. Slash commands handle everything else:

| Command             | What it does                        |
| -------------------- | ------------------------------------ |
| `<game name>`         | queue a mirror for that game         |
| `/status`             | list active mirrors and expiry times |
| `/stop <exe name>`    | stop one mirror                      |
| `/stop all`           | stop every active mirror             |
| `/help`               | show the command list                |
| `/exit` (or blank)    | quit - active mirrors keep running   |

If a game has more than one possible executable, add `--pick` to the game
name to choose which one to use, e.g. `Apex Legends --pick`.

### Skipping the prompt

You can also start a mirror directly from the command line instead of using
the interactive prompt:

```powershell
.\mirror.ps1 -GameName "Roblox"
```

## Notes

- First run downloads and caches Discord's detectable-apps list, refreshed
  every 24h.
- Windows cache/mirror files live under `%LOCALAPPDATA%\quest-mirror\`.
- macOS cache/mirror files live under `~/Library/Caches/quest-mirror/`.
