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

**Windows**: the stub is a renamed copy of `cmd.exe`, launched minimized-off-
screen. Discord's Windows game scanner only picks up processes that own a
window in a normal (non-minimized) state, so the window is moved off every
monitor via `SetWindowPos` instead of being minimized. This behavior has been
confirmed by live testing.

**macOS**: the stub is a renamed copy of `/bin/sleep`, run as a plain
background process. This is a best-effort implementation - Discord's macOS
Quest detection is closed-source and hasn't been confirmed against real
Quests the way the Windows path has. If it doesn't work for you, please open
an issue with what you tried.

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

Nothing to install beforehand - no Homebrew, no admin password. If
[PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-macos)
(`pwsh`) isn't already on your system (macOS doesn't ship it by default; it's
required for Discord's detectable-apps handling and this script's process
management), the installer downloads Microsoft's official portable build
straight from its GitHub releases, verifies it against the published
checksum, and unpacks it into `~/Library/Caches/quest-mirror/pwsh/` -
nothing touches `/usr/local` or any system-wide location. That download only
happens once; later runs reuse it and just re-fetch the latest `mirror.ps1`,
so re-running the same command later also doubles as an update command. To
pass arguments through to `mirror.ps1` (e.g. the non-interactive mode
described below), add `-s --` before them:

```bash
curl -fsSL https://raw.githubusercontent.com/KiarTV/Discord-Quest/master/scripts/install.sh | bash -s -- -GameName "Roblox"
```

If you already have `pwsh` installed and prefer the same one-liner style as
Windows, that also works from inside `pwsh`:

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

## Local dev / non-interactive mode

For faster iteration than the interactive prompt, run the built `mirror.ps1`
directly with parameters:

```powershell
.\mirror.ps1 -GameName "Roblox"              # auto-picks the default exe
.\mirror.ps1 -GameName "Roblox" -ExeChoice 2 # force a specific exe from the list
```

This skips all prompts and is useful for testing changes to the matching or
executable-selection logic without typing input by hand each run.

## Repository layout

`mirror.ps1` at the repo root is a **generated file** - the single-file
script the `irm | iex` one-liners above actually fetch and run. The real
source lives under `src/`, split by concern (game resolution, the mirror
queue, the input/completion-menu loop, and a `Platform/` folder holding the
Windows and macOS-specific mechanics behind a common dispatch layer). After
changing anything under `src/`, rebuild and commit the regenerated file:

```powershell
.\build.ps1
```

See [CLAUDE.md](CLAUDE.md) for the full module breakdown and the invariants
worth knowing before editing the platform-specific pieces.

## Notes

- First run downloads and caches Discord's detectable-apps list, refreshed
  every 24h.
- Windows cache/mirror files live under `%LOCALAPPDATA%\quest-mirror\`.
- macOS cache/mirror files (plus the downloaded portable `pwsh`, if any) live
  under `~/Library/Caches/quest-mirror/`. Delete the `pwsh/` subfolder there
  to force `install.sh` to fetch a fresh PowerShell version.
