# ProjectWorkspaces — Locked Specifications

This document captures the locked architectural decisions, schemas, and contracts so engineers can implement without design decisions. For the active execution plan and phase tracking, see `docs/agent-layer/ROADMAP.md`.

## Scope baseline (what we are building)

We are building a macOS project workspace switcher that:

- Uses **AeroSpace workspaces** as the only workspace container (not macOS Spaces).
- Implements a single primary action: **Activate(project)**
  - Switch to the project’s workspace
  - Ensure the project’s **Chrome window** exists (create if missing)
  - Ensure the project’s **IDE window** exists (create if missing)
  - Apply the project’s saved layout for the current display mode (or defaults)
  - End with the IDE focused
- Provides a global keyboard-first switcher invoked by **⌘⇧Space**.
- Switcher remains visible during activation as a non-key HUD, shows loading/error states, and closes on success after IDE focus.
- Provides a **Close Project** action that closes **every window in the project’s AeroSpace workspace** (closing the workspace by emptying it).
- Persists per-project per-display-mode layout (laptop vs ultrawide).

This roadmap is derived from the requirements spec but intentionally changes the prior “macOS Space pinning” and “Open/Create separation” into an “Activation” model.

## Non-goals (explicit)

- No macOS Spaces pinning, desk labels, or Mission Control navigation.
- No Chrome pinned tabs, no Chrome extension.
- No forced Chrome Profile isolation (per-project profile selection is optional).
- No multi-monitor orchestration. If multiple displays are present, ProjectWorkspaces uses the main display only and warns once.

## Key design decisions (locked)

1) **Container**: AeroSpace workspaces only.
2) **Primary UX**: Activation model only (no Open/Create split).
3) **Switcher hotkey (fixed)**: ⌘⇧Space.
4) **Display modes**: exactly two
   - `laptop`
   - `ultrawide` (Nick’s ultrawide is 5120×1440)
5) **Workspace file storage**: centralized, tool-owned
   - `~/.local/state/project-workspaces/vscode/<projectId>.code-workspace`
6) **Tab seeding**: only when Chrome window is (re)created; no enforcement afterwards.
7) **Close Project**: closes **all windows** in that project workspace.
8) **No per-repo gitignore requirement**.
9) **Implementation language**: Swift.
   - Rationale: stable TCC/Accessibility permissions, reliable global hotkeys, distribution as a signed/notarized app.
10) **Dependency policy**: Third-party Swift dependencies are allowed only for TOML parsing (SwiftPM, version pinned).
11) **Hotkey implementation**: Apple-only via Carbon `RegisterEventHotKey` (no third-party hotkey libraries).
12) **Test policy**: CI runs unit tests only; AeroSpace integration tests are local-only behind `RUN_AEROSPACE_IT=1`.
13) **Logs contract**: Single active log file with deterministic rotation (rotate at 10 MiB, keep 5 archives); activation logs include per-command start/end timestamps + duration.
14) **Fallback workspace**: `pw-inbox` is hard-coded and reserved; `projectId == "inbox"` is invalid and Doctor performs a connectivity check by switching to `pw-inbox` once.
15) **AeroSpace onboarding**: Install a ProjectWorkspaces-safe config at `~/.aerospace.toml` only when no config exists; never modify existing configs; do not use config-based window moving; provide an emergency `aerospace enable off` action.
16) **Build workflow**: Keep a single `ProjectWorkspaces.xcodeproj` in-repo and drive builds/tests/archives via `xcodebuild -project` scripts so the Xcode GUI is not required day-to-day.
17) **Toolchain requirement**: End users do not need Xcode; developers and CI runners require the Apple toolchain (practically: full Xcode installed).
18) **Workspace policy**: Do not add a repo-level `.xcworkspace` in v1; introduce it only if the repo contains 2+ `.xcodeproj` files that must be built together (record the migration in `docs/agent-layer/DECISIONS.md` and update scripts).
19) **SwiftPM reproducibility**: Commit `ProjectWorkspaces.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and ensure CI resolves packages before building (for example via `xcodebuild -resolvePackageDependencies`).

## Definitions

- **Project**: Configured unit of work (typically a repo) identified by `projectId`.
- **Workspace**: An AeroSpace workspace named `pw-<projectId>`.
- **Activation**: Enter project context and ensure required windows exist.
- **IDE**: VS Code or Antigravity.

## Repository deliverables

- `ProjectWorkspaces.app` — menu bar agent (LSUIElement) with switcher UI.
- `pwctl` — optional CLI wrapper for scripting/debugging.
- `doctor` — surfaced through `pwctl doctor` and an in-app “Run Doctor” (both entry points are permanent).

## File system contract (locked)

- Config: `~/.config/project-workspaces/config.toml`
- Generated VS Code workspace files: `~/.local/state/project-workspaces/vscode/*.code-workspace`
- State: `~/.local/state/project-workspaces/state.json`
- Logs (active): `~/.local/state/project-workspaces/logs/workspaces.log`
- Logs (rotated): `~/.local/state/project-workspaces/logs/workspaces.log.1` … `~/.local/state/project-workspaces/logs/workspaces.log.5` (rotate at 10 MiB)

## Config schema (locked)

`~/.config/project-workspaces/config.toml`

Switcher hotkey is fixed to ⌘⇧Space and is not configurable. If `global.switcherHotkey` is present, Doctor emits WARN and the key is ignored (remove it).

```toml
[global]
defaultIde = "vscode"                 # optional; default "vscode" ("vscode" | "antigravity")

# Tabs opened only when a project Chrome window is created
globalChromeUrls = [
  "https://chatgpt.com/",
  "https://gemini.google.com/",
  "https://claude.ai/",
  "https://todoist.com/app"
]

[display]
ultrawideMinWidthPx = 5000            # optional; default 5000

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
repoUrl = "https://github.com/ORG/REPO"  # optional
ide = "vscode"                           # optional; defaults to global.defaultIde (Doctor WARN when omitted)

# IDE launching
ideUseAgentLayerLauncher = true           # optional; default true
ideCommand = ""                           # optional; default ""

# Additional Chrome tabs for this project (only used at Chrome creation)
chromeUrls = []                           # optional; default []
chromeProfileDirectory = "Profile 2"      # optional; Chrome profile directory (see Doctor)
```

### Defaults and doctor severity (locked)

Defaults are required so the tool is easy to configure on a fresh machine. Only structural/safety-critical omissions are Doctor FAIL; everything else uses a deterministic default and is surfaced as Doctor WARN/OK.

Config parsing must tolerate unknown keys (at minimum: tolerate `global.switcherHotkey`) so Doctor can WARN and ignore removed/unsupported keys.

Doctor FAIL if missing/invalid:
- Config file missing or TOML parse error
- No `[[project]]` entries
- Any project missing/invalid: `id` (regex + unique + not `inbox`), `name` (non-empty), `path` (exists), `colorHex` (`#RRGGBB`)
- Required apps not discoverable for the effective IDE selection(s) or Chrome (using Launch Services discovery if config values are omitted)
- Accessibility permission not granted (required for layout)
- Unable to register the global hotkey ⌘⇧Space (conflict / OS denial); if the agent app is running, use the app-reported hotkey status when available, otherwise skip this check and report PASS with a note.

Doctor WARN if present:
- `global.switcherHotkey` (ignored; hotkey is fixed to ⌘⇧Space)

Defaults (applied if keys are missing):

| Key                                | Default                     | Doctor severity when omitted |
| ---------------------------------- | --------------------------- | ---------------------------- |
| `global.defaultIde`                | `"vscode"`                  | WARN                         |
| `global.globalChromeUrls`          | `[]`                        | WARN                         |
| `display.ultrawideMinWidthPx`      | `5000`                      | WARN                         |
| `project.ide`                      | inherit `global.defaultIde` | WARN                         |
| `project.chromeUrls`               | `[]`                        | OK                           |
| `project.chromeProfileDirectory`   | unset                       | OK                           |
| `project.ideUseAgentLayerLauncher` | `true`                      | OK                           |
| `project.ideCommand`               | `""`                        | OK                           |

### Workspace naming

- Workspace name is always: `pw-<projectId>`
- `projectId` must match regex: `^[a-z0-9-]+$` (enforced by doctor and runtime)
- `projectId` must not be `inbox` (reserved for the fallback workspace `pw-inbox`).

## State schema (locked)

`~/.local/state/project-workspaces/state.json`

```json
{
  "version": 1,
  "projects": {
    "codex": {
      "managed": {
        "ideWindowId": 400373,
        "chromeWindowId": 400375
      },
      "layouts": {
        "laptop": {
          "ide": {"x": 0, "y": 0, "width": 1, "height": 1},
          "chrome": {"x": 0, "y": 0, "width": 1, "height": 1}
        },
        "ultrawide": {
          "ide": {"x": 0.25, "y": 0, "width": 0.375, "height": 1},
          "chrome": {"x": 0.625, "y": 0, "width": 0.375, "height": 1}
        }
      }
    }
  }
}
```

Notes:
- State is a cache and may be deleted without data loss (config is source of truth).
- Window IDs are cached to avoid redundant AeroSpace lookups; layouts are stored as normalized rects in visible-frame coordinates.
