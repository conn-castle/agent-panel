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
4) Google Chrome (required for `ap new-chrome` and future activation)
5) VS Code and/or Antigravity (required for `ap new-ide` and future activation)

## First run (onboarding)

On first launch, AgentPanel will prompt to install/configure AeroSpace if needed:

- Installs AeroSpace via Homebrew (if missing)
- Writes a safe `~/.aerospace.toml` (backs up any existing config to `~/.aerospace.toml.agentpanel-backup`)
- Attempts to start AeroSpace

If you decline, AgentPanel quits.

## Configuration

### Path

`~/.config/agent-panel/config.toml`

If the file is missing, AgentPanel creates a starter config with commented guidance and an example.
Until you add at least one `[[project]]`, Doctor will report config failures.

### Schema

```toml
[[project]]
name = "AgentPanel"                    # required; id derived from name
path = "/Users/you/src/agent-panel"    # required; absolute path to the git repo
color = "indigo"                       # required; "#RRGGBB" or named color
useAgentLayer = true                   # required; repo uses an .agent-layer folder
```

The project id is derived by lowercasing the name and replacing any character outside a-z and 0-9 with `-`.
Named colors are: black, blue, brown, cyan, gray, grey, green, indigo, orange, pink, purple, red, teal, white, yellow.

## Paths

- Config: `~/.config/agent-panel/config.toml`
- State (reserved): `~/.local/state/agent-panel/state.json`
- Logs (active): `~/.local/state/agent-panel/logs/agent-panel.log`
- Logs (rotated): `~/.local/state/agent-panel/logs/agent-panel.log.1` … `agent-panel.log.5`
- Logs format: JSON Lines with UTC ISO-8601 timestamps; rotation at 10 MiB
- VS Code workspaces (created by `ap new-ide <identifier>`): `~/.local/state/agent-panel/vscode/<identifier>.code-workspace`
- AeroSpace config (managed): `~/.aerospace.toml` (backup: `~/.aerospace.toml.agentpanel-backup`)

## Doctor

Run from the CLI:

```bash
ap doctor
```

Or use the app menu: **Run Doctor...**

Current checks include:

- Homebrew installed
- AeroSpace.app installed
- `aerospace` CLI available + basic compatibility (required commands/flags)
- Whether AeroSpace is currently running
- Whether `~/.aerospace.toml` is AgentPanel-managed
- VS Code installed
- Google Chrome installed
- Logs directory status
- AgentPanel config parses, and each `project.path` exists
- Agent-layer CLI (`al`) installed (if any project has `useAgentLayer=true`)
- Agent-layer directory exists for projects with `useAgentLayer=true`
- Hotkey registration status (app only)

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
