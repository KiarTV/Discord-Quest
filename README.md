# Discord Quest Game Mirror

Type a game's name, get a process running with that game's exact `.exe` name
- so Discord's Quest detection sees it as "running" - without downloading or
installing anything.

## How it works

Discord Quests check whether a process with a specific `.exe` filename is
running - nothing more. This tool:

1. Looks up the game in Discord's own public list of detectable applications
   to find the exact Windows `.exe` name it checks for.
2. If the raw name you typed doesn't match well, it cross-checks Steam's
   store search to canonicalize the name (e.g. "gta 5" -> "Grand Theft Auto V")
   and retries.
3. Copies `timeout.exe` (a built-in console app, no desktop session needed)
   to a working folder, renamed to match, and runs it minimized for ~17.5
   minutes - a few minutes longer than the 15 minutes most Quests require.
   It has to keep a real (if minimized) window, since Discord's game scanner
   only picks up processes that own a window.

This only affects what your own local Discord client detects. It doesn't
touch your account, other users, or any network service.

## Usage

No download needed - run directly from GitHub:

```powershell
irm https://raw.githubusercontent.com/KiarTV/Discord-Quest/master/mirror.ps1 | iex
```

You'll land in a small prompt (`quest-mirror >`). Type a game name to queue a
mirror for it - each one launches as its own process, so you can queue
several games in parallel. Slash commands handle everything else:

| Command             | What it does                        |
| -------------------- | ------------------------------------ |
| `<game name>`         | queue a mirror for that game         |
| `/status`             | list active mirrors and expiry times |
| `/stop <exe.exe>`     | stop one mirror                      |
| `/stop all`           | stop every active mirror             |
| `/help`               | show the command list                |
| `/exit` (or blank)    | quit - active mirrors keep running   |

## Local dev / non-interactive mode

For faster iteration than the interactive prompt, run the file directly with
parameters:

```powershell
.\mirror.ps1 -GameName "Roblox"              # auto-picks the default exe
.\mirror.ps1 -GameName "Roblox" -ExeChoice 2 # force a specific exe from the list
```

This skips all prompts and is useful for testing changes to the matching or
executable-selection logic without typing input by hand each run.

## Notes

- Windows + PowerShell only.
- First run downloads and caches Discord's detectable-apps list
  (`%LOCALAPPDATA%\quest-mirror\detectable_apps.json`, refreshed every 24h).
- Mirror executables are written to `%LOCALAPPDATA%\quest-mirror\mirrors\`.
