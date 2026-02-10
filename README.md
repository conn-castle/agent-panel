# AgentPanel

AgentPanel is a macOS menu bar app that provides a project switcher UI and a Doctor report for configuration and AeroSpace health.

## What works

- Menu bar app (background agent)
- Menu bar health indicator reflects latest Doctor severity (PASS/WARN/FAIL)
- Global switcher (Cmd+Shift+Space) to list/filter/activate projects
- Project activation: opens IDE + Chrome, organizes windows in AeroSpace workspace
- Chrome tab persistence: URLs captured on project close, restored on activate (snapshot-is-truth)
- LIFO focus stack: "exit project space" returns to last non-project window
- Agent Layer integration: `al sync` + VS Code launch for projects with `useAgentLayer=true`
- SSH remote projects: VS Code Remote-SSH with Doctor path validation
- Close project with automatic focus restoration (stack or workspace fallback)
- Doctor UI in the app menu
- `ap doctor` CLI

## Requirements

1) macOS 15.7+
2) Homebrew (required for Doctor's AeroSpace install action)
3) AeroSpace installed
4) Google Chrome (required for project activation)
5) VS Code (required for project activation)
6) Agent Layer CLI (`al`) — required if any project uses `useAgentLayer=true`

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
[chrome]
pinnedTabs = ["https://dashboard.example.com"]   # optional; always-open tabs for all projects
defaultTabs = ["https://docs.example.com"]        # optional; default tabs when no history
openGitRemote = true                              # optional; auto-open git remote URL

[agentLayer]
enabled = true   # optional; global default for useAgentLayer (default: false)

[[project]]
name = "AgentPanel"                    # required; id derived from name
path = "/Users/you/src/agent-panel"    # required; absolute path to the git repo
color = "indigo"                       # required; "#RRGGBB" or named color
useAgentLayer = false                  # optional; overrides [agentLayer] enabled (default: global value)
chromePinnedTabs = ["https://api.example.com"]    # optional; per-project always-open tabs
chromeDefaultTabs = ["https://jira.example.com"]  # optional; per-project default tabs

[[project]]
name = "Remote ML"
remote = "ssh-remote+nconn@happy-mac.local"     # SSH remote authority
path = "/Users/nconn/project"                   # Remote absolute path
color = "teal"
useAgentLayer = false                           # required for SSH projects (mutually exclusive)
```

**Agent Layer:** The `[agentLayer]` section sets a global default for `useAgentLayer`. Each project can override this with an explicit `useAgentLayer = true` or `false`. When `useAgentLayer` is `true`, AgentPanel injects a `// >>> agent-panel` block into the project's `.vscode/settings.json` (for window identification), runs `al sync` (CWD = project path), and then launches VS Code via `al vscode --no-sync --new-window` (CWD = project path). This keeps Agent Layer environment variables like `CODEX_HOME` while avoiding the current `al vscode` dual-window issue by not passing a positional path. The `al` and `code` CLIs must be installed and on PATH.

**SSH projects:** Set `project.remote` to a VS Code Remote-SSH authority (`ssh-remote+user@host`) and `project.path` to the remote absolute path. AgentPanel writes a `// >>> agent-panel` settings.json block on the remote via SSH (required for window identification) and then launches VS Code via `code --new-window --remote <authority> <remote-path>`. If the remote settings write fails, activation fails loudly. Doctor validates SSH project paths via `ssh test -d` and warns if the remote settings.json is missing the AgentPanel block. SSH projects cannot use Agent Layer: set `useAgentLayer = false` for SSH projects (this is required when `[agentLayer] enabled = true`).

**Chrome tabs:** Chrome tab configuration is optional. When a project is activated and a fresh Chrome window is created, tabs are opened in a single step from the last captured snapshot (verbatim, preserving order). If no snapshot exists (cold start), tabs are computed from always-open URLs (global `pinnedTabs` + per-project `chromePinnedTabs` + git remote if enabled) followed by default tabs. All tab URLs are captured verbatim on project close and persisted across app restarts. If the Chrome window is manually closed before the project is closed, the stale snapshot is automatically deleted so the next activation uses cold-start defaults.

The project id is derived by lowercasing the name and replacing any character outside a-z and 0-9 with `-`.
Named colors are: black, blue, brown, cyan, gray, grey, green, indigo, orange, pink, purple, red, teal, white, yellow.

## Paths

- Config: `~/.config/agent-panel/config.toml`
- State (reserved): `~/.local/state/agent-panel/state.json`
- Logs (active): `~/.local/state/agent-panel/logs/agent-panel.log`
- Logs (rotated): `~/.local/state/agent-panel/logs/agent-panel.log.1` … `agent-panel.log.5`
- Logs format: JSON Lines with UTC ISO-8601 timestamps; rotation at 10 MiB
- Chrome tab snapshots: `~/.local/state/agent-panel/chrome-tabs/<projectId>.json`
- VS Code settings blocks: injected into `<project-path>/.vscode/settings.json` (local/AL projects) or remote via SSH
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
- AgentPanel config parses, and each local `project.path` exists
- SSH project paths validated via `ssh test -d` (exit 0 = pass, 1 = fail, 255 = connection error)
- Agent-layer CLI (`al`) installed (if any project has `useAgentLayer=true`)
- Agent-layer directory exists for local projects with `useAgentLayer=true`
- Hotkey registration status (app only)

## CLI (`ap`)

`ap` is the CLI companion for AgentPanel. It shares the same config file and provides:

- `ap doctor` — run diagnostic checks
- `ap show-config` — display the parsed configuration
- `ap list-projects [query]` — list projects (optionally filtered by query)
- `ap select-project <id>` — activate a project by ID
- `ap close-project <id>` — close a project by ID and restore focus
- `ap return` — exit to the last non-project window without closing the project

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

Optional: install repo-managed git hooks (pre-commit runs `scripts/test.sh`):

```bash
scripts/install_git_hooks.sh
```
