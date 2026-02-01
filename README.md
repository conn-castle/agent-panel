# ProjectWorkspaces

ProjectWorkspaces is a macOS menu bar app that provides **project-first context switching**.

It creates and manages a lightweight "virtual workspace" per project using **AeroSpace workspaces**, so switching projects hides unrelated windows and brings the right ones back with the right layout.

## What it does (behavioral contract)

ProjectWorkspaces implements two primary actions:

1) **Activate Project**
   - Summon the project’s AeroSpace workspace (`pw-<projectId>`)
   - Confirm the focused workspace via `list-workspaces --focused`
   - Load the project’s window bindings (one IDE, one Chrome)
     - Stale bindings are pruned when the window id is missing or mismatched
     - If a role has no binding, activation opens a new window and binds it
   - Move **only bound windows** to the project workspace (unbound windows are untouched)
   - If no bound windows were already on the workspace, reset layout (flatten, balance, `h_tiles`) and resize IDE to a deterministic width
   - End with the IDE focused (Chrome must not steal focus)
   - Activation fails if workspace focus cannot be confirmed or a required window cannot be opened/detected

2) **Close Project**
   - Close **every window** in the project’s AeroSpace workspace (i.e., empty the workspace)
   - If a window belongs to an app configured as “show on all desktops,” closing it may close it globally; this is acceptable.

Activation is CLI-only; it never uses Accessibility geometry or on-screen checks.

The app is designed to be reliable on a fresh machine with explicit setup steps and a `doctor` command.

## Why this exists

When you work on multiple active projects, window sprawl creates disorientation and slows context switching.
This tool enforces a consistent “project workspace” shape:

- 1 managed IDE window (VS Code or Antigravity)
- 1 managed Chrome window

Additional IDE/Chrome windows can exist, but they are **unmanaged** unless explicitly bound and are never moved or resized by activation.

and provides a keyboard-first switcher that brings you to the right context quickly.

## Non-goals

- No macOS Spaces pinning. AeroSpace workspaces are the only container.
- No Chrome pinned tabs and no Chrome extension.
- No enforced Chrome profile isolation.
- No multi-monitor orchestration; activation targets the focused monitor for workspace focus and sizing, and it does not manage unbound windows across displays.

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

- If a bound IDE or Chrome window is closed, activation opens a new window and binds it.
- Activation only reapplies the canonical layout when the workspace is newly opened (no bound windows present); otherwise your existing layout is preserved.

## Canonical layout

When activation opens a workspace with no bound windows present, it resets the layout and applies a deterministic split:

- `flatten-workspace-tree` then `balance-sizes`
- `layout h_tiles` anchored on the IDE window
- IDE width is 60% of the focused monitor’s visible width
  - min IDE 800, min Chrome 500
  - if the screen is too narrow, use 55% of visible width
- IDE ends focused

If the workspace already contains bound windows, activation keeps the current layout and sizes.

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
- Logs (active): `~/.local/state/project-workspaces/logs/workspaces.log`
- Logs (rotated): `~/.local/state/project-workspaces/logs/workspaces.log.1` … `workspaces.log.5`

### Config schema (locked)

`~/.config/project-workspaces/config.toml`

Switcher hotkey is fixed to ⌘⇧Space and is not configurable. If `global.switcherHotkey` is present, Doctor emits WARN and the key is ignored (remove it).

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

### Defaults and doctor severity (locked)

Defaults are required so the tool is easy to configure on a fresh machine. Only structural/safety-critical omissions are Doctor FAIL; everything else uses a deterministic default and is surfaced as Doctor WARN/OK.

Config parsing tolerates unknown keys (for example: `global.switcherHotkey`, `display.*`) so Doctor can WARN and ignore removed/unsupported keys.

Doctor FAIL if missing/invalid:
- Config file missing or TOML parse error
- No `[[project]]` entries
- Any project missing/invalid: `id` (regex + unique + not `inbox`), `name` (non-empty), `path` (exists), `colorHex` (`#RRGGBB`)
- AeroSpace app or CLI missing
- AeroSpace config missing (no config in either supported location)
- AeroSpace config is ambiguous (found in more than one location)
- Required apps not discoverable for the effective IDE selection(s) or Chrome (using Launch Services discovery if config values are omitted)
- Accessibility permission not granted
- Unable to register the global hotkey ⌘⇧Space (conflict / OS denial); if the agent app is running, Doctor uses the app-reported hotkey status when available, otherwise it skips this check and reports PASS with a note.

Doctor WARN if present:
- `global.switcherHotkey` (ignored; hotkey is fixed to ⌘⇧Space)

Defaults (applied if keys are missing):

| Key                                | Default                     | Doctor severity when omitted |
| ---------------------------------- | --------------------------- | ---------------------------- |
| `global.defaultIde`                | `"vscode"`                  | WARN                         |
| `global.globalChromeUrls`          | `[]`                        | WARN                         |
| `project.ide`                      | inherit `global.defaultIde` | WARN                         |
| `project.chromeUrls`               | `[]`                        | WARN                         |

### Workspace naming (locked)

- Workspace name is always: `pw-<projectId>`
- `projectId` must match: `^[a-z0-9-]+$`
- `projectId` must not be `inbox` (reserved for the fallback workspace `pw-inbox`).

## IDE handling

### Supported IDEs

- Visual Studio Code (default)
- Antigravity (VS Code fork)

### IDE resolution (CLI-only activation)

Activation resolves the IDE identity (bundle id + app name) using config and Launch Services. It uses the project’s bound IDE window if present. If no bound IDE window exists (or the binding is stale), activation launches a new IDE window and binds it. Unbound IDE windows are never moved or resized.

## Chrome handling

### Chrome resolution (CLI-only activation)

Activation uses the project’s bound Chrome window if present. If no bound Chrome window exists (or the binding is stale), activation opens a new Chrome window and binds it. Optional `global.globalChromeUrls` and `project.chromeUrls` are opened only when a new window is created. Unbound Chrome windows are never moved or resized.

### Focus behavior

Activation always ends by focusing the IDE window.

## Close Project behavior

Close Project is defined as: **close every window assigned to the project’s AeroSpace workspace**.

This is intentionally aggressive; it closes the virtual workspace by emptying it.

Important note: if you keep a window “show on all desktops” (e.g., Messages), and it appears in the project workspace list, closing the project may close that window globally.

## Security and permissions

- Accessibility permission is required by Doctor checks.
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

### CLI compatibility gate

- Activation verifies required AeroSpace commands (`list-workspaces --focused`, `list-windows --all --json`, `focus --help`, `move-node-to-workspace --help`, `summon-workspace --help`). If any fail, activation stops with a compatibility error.

### Chrome tabs

- Activation only opens URLs when it creates a **new** Chrome window; existing Chrome windows/tabs are not mutated.

### Multi-display behavior

- Activation targets the focused monitor for workspace focus and sizing.
- Bound windows can originate on any monitor; they are moved to the project workspace.
- Unbound windows on other monitors are untouched.

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
- Ensure the IDE and Chrome apps can launch (activation will open and bind a window if needed).
- Check logs for workspace focus or window detection errors.

### VS Code opens but color identity does not apply

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

- Unit tests (CI-required): TOML parsing + defaults/validation, AeroSpace JSON decoding and CLI wrapper behavior using fixtures/mocks
- Integration tests (local-only): gated behind `RUN_AEROSPACE_IT=1` (real AeroSpace + window/session constraints are not CI-friendly)
- Manual integration checks:
  - activation succeeds when bound windows exist, or opens and binds one IDE + one Chrome window when missing
  - unbound IDE/Chrome windows are never moved or resized
  - layout resets to `h_tiles` only when the workspace is newly opened; IDE width is ~60% of visible width

### Engineering implementation notes (locked)

- Third-party Swift dependencies are allowed only for TOML parsing (SwiftPM, version pinned). No other runtime dependencies in v1.
- Global hotkey implementation uses Carbon `RegisterEventHotKey` (no third-party hotkey libraries).
- Activation uses the AeroSpace CLI only (no Accessibility geometry in Core).
- Window discovery uses read-only `list-windows --all --json`; window actions always target explicit `--window-id`.
- All AeroSpace commands execute through a single serialized executor.
- Canonical layout is enforced only when the project workspace is newly opened (no bound windows present).
- No silent failures: show user-facing errors + write structured logs.
