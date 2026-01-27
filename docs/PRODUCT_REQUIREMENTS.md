# ProjectWorkspaces — Product Requirements (PRD)

**Status:** Approved (locked)

**Purpose:** This document defines **what** ProjectWorkspaces must do (user-visible behavior, constraints, acceptance criteria) so engineers can implement without product/architecture decisions.

This PRD supersedes the older macOS-Spaces/pinning model from the original requirements spec and reflects the updated direction:

- **Container:** AeroSpace workspaces (virtual workspaces), not macOS Spaces
- **Lifecycle:** single **Activate** action (idempotent) instead of Open/Create separation
- **Chrome:** no pinned tabs, no extension; tabs are seeded only when the project Chrome window is (re)created
- **Close:** “Close Project” empties the project workspace by closing **every window** assigned to it

---

## 1. Problem

When working on many concurrent projects, window sprawl causes disorientation and makes context switching slow.

ProjectWorkspaces provides **project-first switching** by giving each project a stable, isolated “virtual workspace” containing:

- **One IDE window** (VS Code by default; Antigravity supported)
- **One dedicated Chrome window** for the project

---

## 2. Goals

### 2.1 Primary goals (MUST)

1) **Fast project switching** with low cognitive load
2) Each project has a stable workspace container (AeroSpace workspace)
3) Each project workspace reliably contains:
   - one IDE window
   - one Chrome window
4) **IDE ends focused** after activation (Chrome must not steal focus)
5) Support two display modes with persistent per-project layout:
   - laptop mode
   - ultrawide mode (5120×1440)
6) Repeatable installation and recovery on a fresh machine with:
   - explicit macOS permission requirements
   - a `doctor` command
   - clear logs
7) **No first-run panic**: starting AeroSpace must not immediately tile/resize the user's entire system.
8) **No config clobbering**: existing AeroSpace configs must remain unchanged.
9) **No global takeover**: AeroSpace should only matter for windows managed by ProjectWorkspaces.

### 2.2 Secondary goals (SHOULD)

- Support both VS Code and Antigravity with the **same workflow**
- Allow per-project custom IDE launch commands (repo scripts)
- Allow “global apps” (Slack/Mail/Messages) to exist outside the project model (not managed; not required to be hidden)

---

## 3. Non-goals (explicit)

1) **No macOS Spaces pinning** (no Desk labels, no Mission Control navigation)
2) **No Open/Create toggle**; the UI only supports **Activate** and **Close**
3) **No Chrome pinned tabs** and no Chrome extension
4) **No enforced Chrome Profiles** per project
5) No multi-monitor orchestration as a product requirement
   - If multiple displays exist, behavior is best-effort and must warn in logs

---

## 4. Definitions

- **Project**: a configured unit of work (usually a local repo), identified by a stable `projectId`.
- **Workspace**: an **AeroSpace workspace** named `pw-<projectId>`.
- **Activate(Project)**: switch to the project workspace and ensure its core windows exist.
- **Close(Project)**: close every window in the project workspace.
- **AeroSpace config locations**: `~/.aerospace.toml` and `${XDG_CONFIG_HOME:-~/.config}/aerospace/aerospace.toml`.
- **Safe AeroSpace config**: a ProjectWorkspaces-managed config that floats all windows and defines no keybindings.
- **Display mode**:
  - `laptop`: any main display width < `ultrawideMinWidthPx`
  - `ultrawide`: any main display width ≥ `ultrawideMinWidthPx`

---

## 5. Product surface area

### 5.1 App

- `ProjectWorkspaces.app`: a menu bar background agent (no Dock icon), always-on.

### 5.2 CLI

- `pwctl`: debugging and automation entry point

### 5.3 Files

- Config (source of truth): `~/.config/project-workspaces/config.toml`
- Generated VS Code workspace files: `~/.config/project-workspaces/vscode/<projectId>.code-workspace`
- Runtime state (cache): `~/.local/state/project-workspaces/state.json`
- Logs (active): `~/.local/state/project-workspaces/logs/workspaces.log`
- Logs (rotated): `~/.local/state/project-workspaces/logs/workspaces.log.1` … `~/.local/state/project-workspaces/logs/workspaces.log.5`

---

## 6. Functional requirements

### PR-001 — Project configuration

**MUST**

- Projects are defined exclusively via `config.toml`.
- Adding a new project must require editing only `config.toml`.
- `projectId` must match: `^[a-z0-9-]+$`.
- `projectId` must not be `inbox` (reserved for the fallback workspace `pw-inbox`).

### PR-002 — Config defaults, discovery, and doctor severity

**MUST**

- The tool must apply deterministic defaults for non-structural config omissions and surface omissions as Doctor WARN/OK (table below).
- Doctor must FAIL if any of the following are missing or invalid:
  - config file missing or TOML parse error
  - no `[[project]]` entries
  - any project has missing/invalid `id`, `name`, `path`, or `colorHex` (per PR-001)
  - required apps are not discoverable for the effective IDE selection(s) or Chrome
  - Accessibility permission is not granted (required for layout)
- If `ide.*.appPath` / `bundleId` are omitted, Doctor must attempt app discovery via Launch Services.
- Doctor must print discovered values as a copy/paste config snippet and must not auto-edit `config.toml`.
- Config parsing must tolerate unknown keys so that unsupported keys can be surfaced as WARN instead of becoming a parse failure (at minimum: tolerate `global.switcherHotkey` so it can be WARNed + ignored).
- If `global.switcherHotkey` is present, Doctor must WARN (“Hotkey is fixed to ⌘⇧Space; key is ignored; remove it.”) and runtime must ignore it.

Defaults (applied if keys are missing):

| Key                                | Default                       | Doctor severity when omitted |
| ---------------------------------- | ----------------------------- | ---------------------------- |
| `global.defaultIde`                | `"vscode"`                    | WARN                         |
| `global.globalChromeUrls`          | `[]`                          | WARN                         |
| `display.ultrawideMinWidthPx`      | `5000`                        | WARN                         |
| `project.ide`                      | inherit `global.defaultIde`   | WARN                         |
| `project.chromeUrls`               | `[]`                          | OK                           |
| `project.ideUseAgentLayerLauncher` | `true`                        | OK                           |
| `project.ideCommand`               | `""`                          | OK                           |

### PR-010 — Global switcher UI

**MUST**

- Global hotkey: **⌘⇧Space** opens the switcher.
- Hotkey is fixed to ⌘⇧Space and is not configurable.
- Switcher is keyboard-first:
  - type-to-filter
  - Enter = Activate
  - Esc = dismiss
- Switcher displays project identity:
  - color swatch
  - name

**MUST (Close)**

- In switcher, **⌘W** closes the selected project workspace (Close Project).

### PR-020 — Activate(Project) behavior

**MUST**

Given `projectId`:

1) Switch to workspace `pw-<projectId>`.
2) Ensure IDE window exists in that workspace.
   - If missing, create it.
3) Ensure Chrome window exists in that workspace.
   - If missing, create it.
4) Force IDE and Chrome windows to floating mode (to allow deterministic geometry).
5) Apply layout for the current display mode:
   - use persisted layout if available
   - otherwise use defaults
6) End with IDE focused.

**MUST**

- Activation must never move or adopt windows from other workspaces. It only uses windows already in `pw-<projectId>` and creates new ones in that workspace if missing.

**MUST**

- Activation is **idempotent**:
  - running it repeatedly must not create additional IDE/Chrome windows when the expected windows already exist.

### PR-030 — Close(Project) behavior (“close the workspace”)

**MUST**

- Close(Project) closes **every window assigned to the project’s AeroSpace workspace**.
- This is intentionally aggressive.
- If the user has windows configured “show on all desktops,” closing them may affect them globally. This is acceptable.
- After closing a currently focused project workspace, the app must switch to a fallback workspace:
  - `pw-inbox`
- `pw-inbox` is hard-coded and reserved (not configurable).

### PR-040 — Chrome behavior

**MUST**

- Exactly one Chrome window per project workspace.
- Chrome remains logged in normally (no enforced profiles).
- Tabs are seeded only when the project Chrome window is created/recreated:
  1) `global.globalChromeUrls`
  2) `project.repoUrl` (if set)
  3) `project.chromeUrls`
- After Chrome creation, the app must refocus the IDE.

### PR-050 — IDE behavior

**MUST**

- Supported IDEs: VS Code and Antigravity.
- Global default IDE exists with per-project override.

**MUST (custom launch)**

Per project, IDE launch priority is:

1) If `ideCommand` is non-empty: execute it in project root.
2) Else if `ideUseAgentLayerLauncher=true` and `./.agent-layer/open-vscode.command` exists: execute it in project root.
3) Else: open the effective IDE:
   - VS Code: `open -a <VSCode.appPath> <generatedWorkspaceFile>`
   - Antigravity: `open -a <Antigravity.appPath> <projectPath>`

**MUST (fallback behavior)**

- If `ideCommand`/launcher exits non-zero, log WARN and fall back to the effective IDE open command.
- If the fallback open fails, activation must FAIL with an actionable error.

**MUST (deterministic project identity in IDE)**

- The tool must generate a centralized `.code-workspace` file that applies project identity via VS Code workspace settings.
- If a custom launcher opens VS Code by folder, the tool must follow up by opening the generated workspace file in **reuse-window** mode so colors/settings apply.

**MUST (no assumptions about preconfigured CLIs)**

- The tool must not require users to manually install `code` into PATH.
- The tool must provide a tool-owned `code` shim when it needs to invoke VS Code CLI.

### PR-060 — Layout defaults

**MUST**

- Laptop mode:
  - IDE and Chrome are “maximized” (same visible frame; not macOS fullscreen)
  - IDE ends focused

- Ultrawide mode (5120×1440):
  - split visible frame into 8 equal vertical segments
  - segments 0–1 empty
  - segments 2–4 IDE
  - segments 5–7 Chrome
  - IDE ends focused

### PR-070 — Layout persistence

**MUST**

- Persist layout per project per display mode.
- If user resizes/moves IDE/Chrome, it must be saved (debounced) and restored on next Activate.

### PR-080 — Diagnostics and repeatability

**MUST**

- Provide `pwctl doctor` and an in-app “Run Doctor.”
- Doctor must validate:
  - AeroSpace installed and CLI resolvable (server reachable once safe config is in place)
  - Accessibility permission granted to ProjectWorkspaces
  - Chrome installed
  - VS Code installed (and Antigravity if configured)
  - global hotkey ⌘⇧Space can be registered (FAIL if registration fails due to conflict / OS denial)
  - if the agent app is running, Doctor must skip the hotkey registration check and report PASS with a note that the hotkey is managed by the agent
  - config parses and is valid
  - project paths exist
  - required directories are writable
- Doctor must perform an AeroSpace connectivity check by switching to `pw-inbox` once (and switching back best-effort).
- Failures must be actionable (explicit “Fix:” text).

### PR-085 — AeroSpace onboarding and Doctor (safe config)

**MUST**

- Keep both Doctor entry points:
  - `pwctl doctor`
  - in-app **Run Doctor** (same core engine and identical report output)
- Doctor severity levels are **PASS**, **WARN**, **FAIL**.
- AeroSpace config locations (Doctor checks both, pre-server-start):
  1) `~/.aerospace.toml`
  2) `${XDG_CONFIG_HOME}/aerospace/aerospace.toml` where `XDG_CONFIG_HOME` defaults to `~/.config` if unset
- Reserved workspace: `pw-inbox` is hard-coded and always safe to switch to.

**Safe config (ProjectWorkspaces-safe)**

- Floats all windows by default.
- Defines **no AeroSpace keybindings**.
- Contains **no move-node-to-workspace** rules.

Template (installed only when no config exists):

```toml
# Managed by ProjectWorkspaces.
# Purpose: prevent AeroSpace default tiling from affecting all windows.
# This config intentionally defines no AeroSpace keybindings.
config-version = 2

[mode.main.binding]
# Intentionally empty. ProjectWorkspaces provides the global UX.

[[on-window-detected]]
check-further-callbacks = true
run = 'layout floating'
```

**Hard-locked policies**

- Switcher hotkey is fixed to **Cmd+Shift+Space**; any attempt to set it in config is ignored and must produce a Doctor WARN.
- If **no AeroSpace config exists**, ProjectWorkspaces installs the safe config at `~/.aerospace.toml`.
- If **any AeroSpace config exists**, ProjectWorkspaces must **not** write or modify config files and must run in compatibility mode.
- ProjectWorkspaces must never install `on-window-detected` rules that move windows to workspaces by `app-id`.

**Doctor report header (exact)**

```
ProjectWorkspaces Doctor Report
Timestamp: <ISO-8601>
ProjectWorkspaces version: <semver or git sha>
macOS version: <string>
AeroSpace app: <detected path or NOT FOUND>
aerospace CLI: <resolved absolute path or NOT FOUND>
```

**Doctor decision tree (exact text)**

Doctor entry UI strings (exact)

- In-app menu item: `Run Doctor...`
- Doctor window title: `Doctor`
- Primary buttons:
  - `Run Doctor`
  - `Copy Report`
  - `Install Safe AeroSpace Config`
  - `Start AeroSpace`
  - `Reload AeroSpace Config`
  - `Emergency: Disable AeroSpace`
  - `Close`

Step 1 — Detect AeroSpace installation

- PASS: `PASS  AeroSpace.app found at: /Applications/AeroSpace.app`
- FAIL: `FAIL  AeroSpace.app not found in /Applications`
  - `Fix: Install AeroSpace (recommended: Homebrew cask). Then re-run Doctor.`
- PASS: `PASS  aerospace CLI found at: <absolute path>`
- FAIL: `FAIL  aerospace CLI not found`
  - `Fix: Ensure AeroSpace CLI is installed and available. Re-run Doctor.`

Step 2 — Detect AeroSpace config state

- Ambiguous (both exist):
  - `FAIL  AeroSpace config is ambiguous (found in more than one location).`
  - `Detected:`
    - `- ~/.aerospace.toml`
    - `- <resolved XDG path>`
  - `Fix: Remove or rename one of the files, then re-run Doctor. ProjectWorkspaces will not pick one automatically.`
- Existing (exactly one exists):
  - `PASS  Existing AeroSpace config detected. ProjectWorkspaces will not modify it.`
  - `Config location: <path>`
  - `Note: Your AeroSpace config may tile/resize windows. If you don't want that, update your AeroSpace config yourself. ProjectWorkspaces does not change it automatically.`
- Missing (none exist):
  - `FAIL  No AeroSpace config found. Starting AeroSpace will load the default tiling config and may resize/tile all windows.`
  - `Recommended fix: Install the ProjectWorkspaces-safe config which floats all windows by default.`

Step 3 — Install safe config (single click)

- Re-check both config locations; abort if any exist.
- Write atomically to `~/.aerospace.toml` via temp file + fsync + rename.
- Verify marker line `# Managed by ProjectWorkspaces.`.
- Report:
  - `PASS  Installed safe AeroSpace config at: ~/.aerospace.toml`
  - `Next: Start AeroSpace`

Step 4 — Start AeroSpace

- Query: `aerospace config --config-path`; if that fails, try `aerospace list-workspaces --focused`.
- If both fail, run `open -a /Applications/AeroSpace.app` and retry up to 20 times with 250ms delay.
- PASS: `PASS  AeroSpace server is running`
- FAIL: `FAIL  Unable to connect to AeroSpace server`
  - `Fix: Launch AeroSpace manually and ensure required permissions are granted. Re-run Doctor.`
- Once connected: `PASS  AeroSpace loaded config: <path>`

Step 5 — Connectivity / disruption check (pw-inbox switch)

- Always show: `INFO  Current workspace before test: <prev>`
- PASS: `PASS  AeroSpace workspace switch succeeded (pw-inbox)`
- PASS: `PASS  Restored previous workspace: <prev>`
- WARN: `WARN  Could not restore previous workspace automatically.`
  - `Fix: Run: aerospace workspace <prev>`
- FAIL: `FAIL  AeroSpace workspace switching failed. ProjectWorkspaces cannot operate safely.`

Step 6 — Emergency action (panic button)

- Action: `aerospace enable off`
- Output: `PASS  Disabled AeroSpace window management (all hidden workspaces made visible).`

**Restore / uninstall (safe config only)**

- If `~/.aerospace.toml` contains the marker as the first non-empty line, Doctor may offer **Uninstall Safe AeroSpace Config**:
  1) Rename `~/.aerospace.toml` to `~/.aerospace.toml.projectworkspaces.bak.<YYYYMMDD-HHMMSS>`
  2) If AeroSpace is running, run `aerospace reload-config --no-gui` (WARN on failure)
- Output:
  - `PASS  Backed up ~/.aerospace.toml to: <backup path>`
  - `INFO  AeroSpace will now use default config unless you provide your own config.`
- If marker is missing: show
  - `INFO  AeroSpace config appears user-managed; ProjectWorkspaces will not modify it.`

### PR-090 — Logging

**MUST**

- The active log file path is stable: `~/.local/state/project-workspaces/logs/workspaces.log`.
- Rotate logs when the active log exceeds 10 MiB; keep `workspaces.log.1` through `workspaces.log.5` (max 5 archives).
- Every Activate and Close action must log:
  - timestamp
  - projectId
  - workspaceName
  - AeroSpace command invocations and stdout/stderr
  - final result (success/warn/fail)
- No silent failures.

---

## 7. Non-functional requirements

### NFR-001 — Reliability

- Activation must succeed in the common case without manual intervention.
- If it cannot succeed (missing permissions, missing app), errors must be explicit and actionable.

### NFR-002 — Performance

- Switcher must appear quickly.
- Activation should feel near-instant when windows already exist.

### NFR-003 — Security / system constraints

- Must not require SIP disabling.
- Must use documented macOS permissions (Accessibility) and make them explicit in setup.

### NFR-004 — Maintainability

- Config schema is versioned.
- State is a cache; deleting state must not destroy the ability to use the tool.

### NFR-005 — Distribution and toolchain

- End users must not be required to install Xcode.
- Developers and CI runners require the Apple build toolchain (practically: full Xcode installed).
- Common build/test/release workflows must be runnable from the command line (Xcode GUI optional day-to-day), using `xcodebuild`-driven scripts.
- The canonical repo entrypoint is `ProjectWorkspaces.xcodeproj` (no repo-level `.xcworkspace` in v1).
- Build/test scripts must use `xcodebuild -project ProjectWorkspaces.xcodeproj ...`.
- Introduce a repo-level `.xcworkspace` only if the repo contains 2+ `.xcodeproj` files that must be built together; if so, update scripts and record the migration in `docs/agent-layer/DECISIONS.md`.
- Commit `Package.resolved` for reproducible SwiftPM dependency resolution; CI must resolve packages before building (e.g., `xcodebuild -resolvePackageDependencies`).
- In this repo, the expected SwiftPM lockfile path is `ProjectWorkspaces.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (commit this file; do not add duplicate copies).
- The release artifact is a signed + notarized `.app`, shipped via both a Homebrew cask (recommended) and a direct download (`.zip` or `.dmg`).

### NFR-006 — Platform support

- The minimum supported macOS version is 15.7.

---

## 8. Acceptance criteria (end-to-end)

The product is acceptable when all tests below pass:

1) **Activate creates missing windows**
   - Starting from an empty workspace, Activate(Project) opens IDE and Chrome and ends with IDE focused.

2) **Activate is idempotent**
   - Re-running Activate does not create additional IDE/Chrome windows.

3) **Chrome focus rule**
   - After activation, IDE is focused even if Chrome was launched.

4) **Ultrawide layout default**
   - On 5120×1440, default layout uses the 2/8 empty + 3/8 IDE + 3/8 Chrome split.

5) **Layout persistence**
   - After user resizes, activation restores the custom geometry.

6) **Close empties the workspace**
   - Close(Project) closes every window in that project workspace.
   - Next Activate recreates missing windows.

7) **Doctor works**
   - On a fresh macOS machine, following README + Doctor results in a working system.

---

## 9. Future candidates (explicitly not committed)

These are possible later additions but are not part of v1 scope:

- Notifications / attention system
- Gesture invocation
- Support for additional browsers or IDEs
- Workspace templates beyond IDE+Chrome
