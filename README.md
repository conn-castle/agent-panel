# AgentPanel

AgentPanel is a macOS menu bar app that provides a project switcher UI and a Doctor report for configuration and AeroSpace health.

The switcher currently **lists projects and logs selections**. Project activation/workspace management is intentionally stubbed for now.

## What works

- Menu bar app (background agent)
- Global switcher (Cmd+Shift+Space) to list/filter projects
- Doctor UI in the app menu
- `ap doctor` CLI

## What is stubbed

- Project activation and workspace management (selection only logs for now)

## Requirements

1) macOS 15.7+
2) Homebrew (required for Doctor's AeroSpace install action)
3) AeroSpace installed
4) Google Chrome
5) VS Code and/or Antigravity

## Configuration

### Path

`~/.config/agent-panel/config.toml`

### Schema

```toml
[global]
defaultIde = "vscode"                 # optional; default "vscode" ("vscode" | "antigravity")
globalChromeUrls = []                 # optional; URLs opened when a new project Chrome window is created

[ide.vscode]
appPath = "/Applications/Visual Studio Code.app"  # optional; omit to auto-discover via Launch Services
bundleId = "com.microsoft.VSCode"                 # optional; omit to auto-discover via Launch Services

[ide.antigravity]
appPath = "/Applications/Antigravity.app"         # optional; omit to auto-discover via Launch Services
# bundleId omitted on purpose; doctor can discover and print it as a copy/paste snippet

[[project]]
id = "codex"
name = "Codex"
path = "/Users/nick/src/codex"
colorHex = "#7C3AED"

# optional per-project override; defaults to global.defaultIde (Doctor WARN when omitted)
ide = "vscode"

# optional; URLs opened when a new Chrome window is created for this project
chromeUrls = []

# optional; Chrome profile directory to use when opening a new Chrome window
chromeProfileDirectory = "Profile 2"
```

## Paths

- Config: `~/.config/agent-panel/config.toml`
- Logs (active): `~/.local/state/agent-panel/logs/agent-panel.log`
- Logs (rotated): `~/.local/state/agent-panel/logs/agent-panel.log.1` … `agent-panel.log.5`

## Doctor

Run from the CLI:

```bash
ap doctor
```

Or use the app menu: **Run Doctor...**

## CLI (`ap`)

`ap` is the CLI companion for AgentPanel. It shares the same config file and provides:

- `ap doctor`
- `ap list-workspaces`
- `ap show-config`
- `ap new-workspace <name>`
- `ap new-ide <identifier>`
- `ap new-chrome <identifier>`
- `ap list-ide`
- `ap list-chrome`
- `ap list-windows <workspace>`
- `ap focused-window`
- `ap move-window <workspace> <window-id>`
- `ap focus-window <window-id>`
- `ap close-workspace <workspace>`

## Development

Canonical entrypoint: `AgentPanel.xcodeproj` (generated via XcodeGen).

Regenerate the project:

```bash
scripts/regenerate_xcodeproj.sh
```

Build:

```bash
scripts/build.sh
```

Test:

```bash
scripts/test.sh
```
