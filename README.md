# Open in Claude

A small, portable launcher: pick a folder (or drag one in, or reuse a recent one) and open it
as a **new Claude Desktop "Code" session**. Dark, minimal, Claude-styled.

No install, no admin. It just fires the app's own deep link:

```
claude://code/new?folder=<your folder>
```

…which opens a new Code session in that folder whether the Desktop app is running or not.

## Run it

- **Quick:** double-click **`Open in Claude.cmd`** (a console may flash briefly), or
- **Direct:** `powershell -ExecutionPolicy Bypass -File OpenInClaude.ps1`

## Use it

1. **Choose folder…** (native picker), **drag a folder** onto the window, or click a **Recent** entry.
2. Hit **Open in Claude** (or double-click a recent) → the Desktop app opens a new session there.
3. First time per folder, Windows/Claude shows a one-time *"Trust this Workspace?"* prompt — approve it.

Recent folders are remembered between runs (stored in `%APPDATA%\OpenInClaude\recents.json`).

## Make a clean .exe (optional)

For a double-clickable executable with no console flash and an icon:

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

This installs the `ps2exe` module (current user) and produces `OpenInClaude.exe`. Drop an
`icon.ico` next to the script first if you want a custom icon; otherwise it builds without one.

## Files

| File | Purpose |
|------|---------|
| `OpenInClaude.ps1` | The app (WPF UI + logic) |
| `Open in Claude.cmd` | Dev launcher (runs the .ps1 hidden) |
| `build.ps1` | Compiles to `OpenInClaude.exe` via ps2exe |
| `README.md` | This file |

## Requirements

Windows 10/11 with the Claude Desktop app installed (registers the `claude://` protocol).
Tested against Claude Desktop v1.9659.2.0.
