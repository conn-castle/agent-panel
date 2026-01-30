# ProjectWorkspaces

ProjectWorkspaces is a macOS menu bar app that provides **project-first context switching**.

It creates and manages a lightweight "virtual workspace" per project using **AeroSpace workspaces**, so switching projects hides unrelated windows and brings the right ones back with the right layout.

## What it does (behavioral contract)

ProjectWorkspaces implements two primary actions:

1) **Activate Project**
   - Switch to the project’s AeroSpace workspace (`pw-<projectId>`)
   - Ensure a project IDE window exists (create if missing)
   - Ensure a project Chrome window exists (create if missing)
   - Only scan/move windows outside `pw-<projectId>` when they carry a ProjectWorkspaces token (no guessing or fallbacks)
   - Apply the project’s saved layout for the current display mode
   - End with the IDE focused (Chrome must not steal focus)

2) **Close Project**
   - Close **every window** in the project’s AeroSpace workspace (i.e., empty the workspace)
   - If a window belongs to an app configured as “show on all desktops,” closing it may close it globally; this is acceptable.

The app is designed to be reliable on a fresh machine with explicit setup steps and a `doctor` command.

## Why this exists

When you work on multiple active projects, window sprawl creates disorientation and slows context switching.
This tool enforces a consistent “project workspace” shape:

- 1 IDE window (VS Code or Antigravity)
- 1 dedicated Chrome window

and provides a keyboard-first switcher that brings you to the right context quickly.

## Non-goals

- No macOS Spaces pinning. AeroSpace workspaces are the only container.
- No Chrome pinned tabs and no Chrome extension.
- No enforced Chrome profile isolation.
- No multi-monitor orchestration; ProjectWorkspaces uses the main display only and warns when multiple displays are present.

## User workflow

### Global switcher

- Hotkey: **⌘⇧Space** (press again to dismiss when browsing; during loading it focuses the switcher)
- Type to filter projects
- Press **Enter** to Activate (switcher stays visible while loading)
- Press **Esc** to dismiss when browsing; during loading, press ⌘⇧Space to focus the switcher, then Esc cancels
- Press **⌘W** to Close the selected project
- During activation, the switcher is a non-key HUD with a loading indicator; on success it closes and IDE is focused
- If the hotkey is unavailable, the menu bar shows **Hotkey unavailable** and **Open Switcher...** opens it manually.

### Day-to-day

- If you close the IDE or Chrome window, the next Activate recreates it.
- If you resize windows, the layout is saved and restored for that project in that display mode.

## Display modes and layouts

The app supports exactly two display modes:

1) **Laptop mode**
   - Both IDE and Chrome are “maximized” (not macOS fullscreen)
   - IDE ends focused

2) **Ultrawide mode** (5120×1440)
   - The screen is split into 8 equal vertical segments:
     - segments 0–1: empty
     - segments 2–4: IDE
     - segments 5–7: Chrome
   - IDE ends focused

Layouts are persisted **per project per display mode**.

## Installation

### Prerequisites

1) macOS 15.7+
2) **Homebrew** (required for AeroSpace install; manual installs not supported yet)
3) **AeroSpace installed** (Doctor will start it once a safe config is in place)
4) Accessibility permission for `ProjectWorkspaces.app`
5) Google Chrome
6) VS Code and/or Antigravity

### Install AeroSpace

Install via Homebrew (required):

```bash
brew install --cask nikitabobko/tap/aerospace
```

Or run Doctor and click **Install AeroSpace** (uses Homebrew).

Manual AeroSpace installs are not supported yet.

### Install ProjectWorkspaces

ProjectWorkspaces will be distributed as a signed + notarized `.app` via:

- Homebrew cask (recommended) — planned
- Direct download (`.zip` or `.dmg`) — planned

**Note:** Distribution is not yet available. See `docs/agent-layer/ROADMAP.md` for status.

### Grant Accessibility permission

System Settings → Privacy & Security → Accessibility:

- Enable `ProjectWorkspaces`

### Run doctor

Run:

```bash
pwctl doctor
```

Doctor must show PASS for:

- Homebrew available
- AeroSpace installed + CLI resolvable
- AeroSpace config is non-ambiguous (or intentionally user-managed)
- AeroSpace server running and loaded config path
- Accessibility permission granted
- Chrome installed
- Global hotkey ⌘⇧Space can be registered
- Config parses and projects are valid
- Project paths exist

Warnings are expected when optional config keys are omitted and defaults are applied.

### AeroSpace onboarding (safe config)

Doctor checks both AeroSpace config locations:

- `~/.aerospace.toml`
- `${XDG_CONFIG_HOME:-~/.config}/aerospace/aerospace.toml`

If **no config exists**, Doctor FAILs to prevent “tiling shock” and offers **Install Safe AeroSpace Config** (in-app). The safe config:

- Floats all windows by default
- Defines no AeroSpace keybindings
- Contains no config-based window moving rules
- Writes to `~/.aerospace.toml` only when no config exists

If **both configs exist**, Doctor FAILs with an ambiguity message. You must remove or rename one; ProjectWorkspaces does not choose for you.

If **exactly one config exists**, Doctor will not modify it.

Emergency: **Disable AeroSpace** is available in the app menu and Doctor window. It runs `aerospace enable off` to immediately disable window management.

If the safe config was installed by ProjectWorkspaces, Doctor offers **Uninstall Safe AeroSpace Config**, which renames `~/.aerospace.toml` to a timestamped `.projectworkspaces.bak` file.

## Configuration

### Paths

- Config: `~/.config/project-workspaces/config.toml`
- Generated VS Code workspace files: `~/.local/state/project-workspaces/vscode/*.code-workspace`
- State: `~/.local/state/project-workspaces/state.json`

### Config schema (locked)

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

# optional per-project override; defaults to global.defaultIde (Doctor WARN when omitted)
ide = "vscode"

# IDE launching
ideUseAgentLayerLauncher = true           # optional; default true
ideCommand = ""                           # optional; default ""

# Additional Chrome tabs (only used when Chrome window is created)
chromeUrls = []                           # optional; default []
chromeProfileDirectory = "Profile 2"      # optional; Chrome profile directory (see `pwctl doctor`)
```

### Defaults and doctor severity (locked)

Defaults are required so the tool is easy to configure on a fresh machine. Only structural/safety-critical omissions are Doctor FAIL; everything else uses a deterministic default and is surfaced as Doctor WARN/OK.

Config parsing tolerates unknown keys (at minimum: `global.switcherHotkey`) so Doctor can WARN and ignore removed/unsupported keys.

Doctor FAIL if missing/invalid:
- Config file missing or TOML parse error
- No `[[project]]` entries
- Any project missing/invalid: `id` (regex + unique + not `inbox`), `name` (non-empty), `path` (exists), `colorHex` (`#RRGGBB`)
- AeroSpace app or CLI missing
- AeroSpace config missing (no config in either supported location)
- AeroSpace config is ambiguous (found in more than one location)
- Required apps not discoverable for the effective IDE selection(s) or Chrome (using Launch Services discovery if config values are omitted)
- Accessibility permission not granted (required for layout)
- Unable to register the global hotkey ⌘⇧Space (conflict / OS denial); if the agent app is running, Doctor uses the app-reported hotkey status when available, otherwise it skips this check and reports PASS with a note.

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

### Workspace naming (locked)

- Workspace name is always: `pw-<projectId>`
- `projectId` must match: `^[a-z0-9-]+$`
- `projectId` must not be `inbox` (reserved for the fallback workspace `pw-inbox`).

## IDE handling

### Supported IDEs

- Visual Studio Code (default)
- Antigravity (VS Code fork)

### How IDE launching works (deterministic)

For each project, the app generates a centralized VS Code workspace file:

- `~/.local/state/project-workspaces/vscode/<projectId>.code-workspace`

This file:

- opens the repo folder
- applies project visual identity via `workbench.colorCustomizations` (title/status/activity bars)
- sets `window.title` to include a deterministic token (`PW:<projectId>`) for window identification

Launch priority (no ambiguity):

1) If `project.ideCommand` is non-empty: run it in the project root via `/bin/zsh -lc`.
2) Else if `project.ideUseAgentLayerLauncher=true` and `<repo>/.agent-layer/open-vscode.command` exists: run that script.
3) Else open the effective IDE:
   - VS Code: `open -a <VSCode.appPath> <generatedWorkspaceFile>`
   - Antigravity: `open -a <Antigravity.appPath> <generatedWorkspaceFile>`

If step 1 or 2 exits non-zero, the app logs WARN and falls back to the same “open” command for the effective IDE. If the fallback open fails, activation fails with an actionable error.

`ideCommand`/launcher environment (always exported):

- `PW_PROJECT_ID`
- `PW_PROJECT_NAME`
- `PW_PROJECT_PATH`
- `PW_WORKSPACE_FILE`
- `PW_REPO_URL`
- `PW_COLOR_HEX`
- `PW_IDE` (`vscode` or `antigravity`)
- `OPEN_VSCODE_NO_CLOSE=1`

#### Ensuring the workspace file (and colors) take effect

Custom launch scripts may open VS Code with the folder path, not the `.code-workspace`. To make project colors deterministic, after any VS Code launch the app runs VS Code CLI in reuse mode against the generated workspace file.

To avoid relying on the user having installed `code` into PATH, the app installs and uses a tool-owned `code` shim:

- Shim path: `~/.local/share/project-workspaces/bin/code`
- The shim invokes VS Code’s bundled CLI inside the VS Code app bundle.

When the app runs any `ideCommand` or agent-layer launcher it prepends this shim directory to PATH.

## Chrome handling

### One Chrome window per project (enforced by deterministic token)

The “project Chrome window” is the Chrome window whose title contains the token `PW:<projectId>` followed by a non-word character or end of string. ProjectWorkspaces launches Chrome with a deterministic window name (and optional profile directory).
ProjectWorkspaces enumerates only `pw-<projectId>`. If the window was just launched and doesn’t appear there, it uses focused-window recovery to capture the new Chrome window and move it into the workspace (no global scan).
If multiple tokened Chrome windows are found in the workspace, activation warns and chooses the lowest window id deterministically.

### Tab seeding (creation-only)

Tabs are opened **only when the project Chrome window is created/recreated**:

1) `global.globalChromeUrls`
2) `project.repoUrl` (if set)
3) `project.chromeUrls`

Duplicate URLs are deduped by exact string match, preserving first occurrence order.

If the computed URL list is empty, ProjectWorkspaces opens a single `about:blank` tab to make window creation deterministic.

If the Chrome window already exists, the app does not modify tabs.

### Chrome profile selection (optional)

If you set `project.chromeProfileDirectory`, ProjectWorkspaces launches Chrome with:

```
open -na "Google Chrome" --args --new-window --window-name="PW:<projectId>" --profile-directory="<profileDir>"
```

Use `pwctl doctor` to list available Chrome profile directory names from Chrome's Local State file.

### Focus behavior

Activation always ends by focusing the IDE window.

## Close Project behavior

Close Project is defined as: **close every window assigned to the project’s AeroSpace workspace**.

This is intentionally aggressive; it closes the virtual workspace by emptying it.

Important note: if you keep a window “show on all desktops” (e.g., Messages), and it appears in the project workspace list, closing the project may close that window globally.

## Security and permissions

- Accessibility permission is required for window geometry control.
- No SIP disabling is required or allowed.
- Running `pwctl doctor` will prompt for Accessibility permission if it is missing.

## CLI (`pwctl`)

`pwctl` exists for debugging, CI-style checks, and as a fallback interface if the UI is unavailable.

Commands (locked surface):

```bash
pwctl doctor
pwctl list
pwctl activate <projectId>
pwctl close <projectId>
pwctl logs --tail 200
```

Exit codes:

- `doctor`: non-zero if any FAIL
- `activate`: non-zero on unrecoverable errors (e.g., missing project path)
- `close`: non-zero only if AeroSpace command execution fails; per-window close failures are WARN

## Behavior details

### Workspace lifecycle

- Each project uses a workspace named `pw-<projectId>`.
- Workspaces persist even when empty.
- Closing the active project switches to `pw-inbox`.
- `pw-inbox` is hard-coded and reserved; `projectId="inbox"` is invalid.

### Chrome tabs

- Tabs are seeded only when the project Chrome window is created.
- Existing Chrome windows are not mutated.

### Multi-display behavior

- Primary supported use case is one display at a time.
- If multiple displays are detected, the app must:
  1) warn once that ProjectWorkspaces uses the main display only,
  2) apply/persist layouts only for windows already on the main display,
  3) skip layout for off-main windows without attempting cross-display moves.

## Logging

- Logs directory: `~/.local/state/project-workspaces/logs/`
- Active log: `~/.local/state/project-workspaces/logs/workspaces.log`
- Rotation: rotate at 10 MiB, keep `workspaces.log.1`…`workspaces.log.5` (max 5 archives)
- `list-windows` outputs are sanitized in logs (window IDs + bundle IDs only; no window titles)
- Every `Activate` and `Close` action must log:
  - timestamp
  - projectId
  - workspaceName
  - per-command start/end timestamps + durationMs
  - AeroSpace stdout/stderr for each command
  - final outcome (success/warn/fail)

## Troubleshooting

### Switcher does not appear

- Confirm `ProjectWorkspaces.app` is running (menu bar).
- Confirm Accessibility permission is enabled for the app.

### Activation switches workspace but windows do not appear

- Run `pwctl doctor` and fix any FAIL items.
- Confirm AeroSpace is running and `aerospace` CLI is resolvable.
- Check logs for IDE/Chrome launch failures.

### VS Code opens but color identity does not apply

- Ensure the generated `.code-workspace` exists under `~/.local/state/project-workspaces/vscode/`.
- Ensure `colorHex` is valid `#RRGGBB`.

### Custom IDE command fails

- The app logs stdout/stderr and falls back to opening the generated workspace file.

### Chrome steals focus

- This is a bug. Activation must always focus the IDE at the end.

## Development

### Build targets

- `ProjectWorkspaces.app` — SwiftUI menu bar agent
- `pwctl` — CLI

### Toolchain (developers / CI)

End users do not need Xcode. Developers and CI runners do: building a native Swift/SwiftUI macOS app (and signing/notarization) requires Apple’s toolchain (practically: full Xcode installed).

Opening the Xcode GUI is optional day-to-day; common workflows are driven by `scripts/build.sh` and `scripts/test.sh` (see `docs/agent-layer/COMMANDS.md`).

Canonical entrypoint (locked): `ProjectWorkspaces.xcodeproj` (do not add a repo-level `.xcworkspace` unless the repo contains 2+ `.xcodeproj` files that must be built together).

Xcode project definition: edit `project.yml`, then regenerate `ProjectWorkspaces.xcodeproj` via `scripts/regenerate_xcodeproj.sh`.

SwiftPM lockfile path (once dependencies are added): `ProjectWorkspaces.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (commit this file).

### Local development

Recommended (no Xcode UI required):

1) (When changing targets/settings) Run `scripts/regenerate_xcodeproj.sh`.
2) Build/test using `scripts/build.sh` and `scripts/test.sh` (see `docs/agent-layer/COMMANDS.md`).
3) Grant Accessibility permission to the debug build.
4) Use `pwctl doctor` during iteration. Run `pwctl activate <projectId>` to test activation behavior.

Optional:
- Open the project in Xcode for occasional debugging/provisioning tasks.

### Testing (required)

- Unit tests (CI-required): TOML parsing + defaults/validation, state read/write, AeroSpace JSON decoding and CLI wrapper behavior using fixtures/mocks
- Integration tests (local-only): gated behind `RUN_AEROSPACE_IT=1` (real AeroSpace + window/session constraints are not CI-friendly)
- Manual integration checks:
  - activation idempotence (no duplicate IDE/Chrome windows)
  - Chrome recreation after manual close (verify tabs open in order: global -> repoUrl -> project)
  - layout persistence per display mode

### Engineering implementation notes (locked)

- Third-party Swift dependencies are allowed only for TOML parsing (SwiftPM, version pinned). No other runtime dependencies in v1.
- Global hotkey implementation uses Carbon `RegisterEventHotKey` (no third-party hotkey libraries).
- Geometry/persistence uses Accessibility (AX) APIs.
- Apply geometry using:
  1) `aerospace focus --window-id <id>`
  2) read/write the system-wide focused window via AX
- Detect newly created IDE/Chrome windows by matching deterministic tokens in `aerospace list-windows --workspace pw-<projectId> --json --format '%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title} %{window-layout}'` output; warn+choose lowest id on multiple matches; if none appear after launch, attempt focused-window recovery via `list-windows --focused` and move into the workspace, otherwise fail loudly.
- No silent failures: show user-facing errors + write structured logs.
