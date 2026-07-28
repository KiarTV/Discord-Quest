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
   to a working folder, renamed to match, and runs it hidden for ~17.5
   minutes - a few minutes longer than the 15 minutes most Quests require.

This only affects what your own local Discord client detects. It doesn't
touch your account, other users, or any network service.

## Usage

No download needed - run directly from GitHub:

```powershell
irm https://raw.githubusercontent.com/<you>/<repo>/main/mirror.ps1 | iex
```

You'll be prompted for a game name, and can keep entering more - each one
launches as its own process, so you can queue several games in parallel.
Press Enter on a blank line to finish. To stop a mirror early, enter
`stop <exe.exe>` (the exe name it printed when it started).

## Notes

- Windows + PowerShell only.
- First run downloads and caches Discord's detectable-apps list
  (`%LOCALAPPDATA%\quest-mirror\detectable_apps.json`, refreshed every 24h).
- Mirror executables are written to `%LOCALAPPDATA%\quest-mirror\mirrors\`.
