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

- **One managed IDE window** (VS Code by default; Antigravity supported)
- **One managed Chrome window** for the project

Additional IDE/Chrome windows are allowed but are **unmanaged** unless explicitly bound.

---

## 2. Goals

### 2.1 Primary goals (MUST)

1) **Fast project switching** with low cognitive load
2) Each project has a stable workspace container (AeroSpace workspace)
3) Each project workspace reliably contains:
   - one IDE window
   - one Chrome window
4) **IDE ends focused** after activation (Chrome must not steal focus)
5) Apply a canonical deterministic layout **when the workspace is newly opened** (no bound windows present):
   - reset tree + balance sizes
   - `h_tiles` layout with a deterministic IDE width based on the focused monitor
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
   - Activation targets the focused monitor for workspace focus and sizing; unbound windows are never moved across displays

---

## 4. Definitions

- **Project**: a configured unit of work (usually a local repo), identified by a stable `projectId`.
- **Workspace**: an **AeroSpace workspace** named `pw-<projectId>`.
- **Activate(Project)**: switch to the project workspace, ensure bound IDE/Chrome windows exist (opening new ones if needed), and move bound windows into the workspace.
- **Close(Project)**: close every window in the project workspace.
- **AeroSpace config locations**: `~/.aerospace.toml` and `${XDG_CONFIG_HOME:-~/.config}/aerospace/aerospace.toml`.
- **Safe AeroSpace config**: a ProjectWorkspaces-managed config that floats all windows and defines no keybindings.

---

## 5. Product surface area

### 5.1 App

- `ProjectWorkspaces.app`: a menu bar background agent (no Dock icon), always-on.

### 5.2 CLI

- `pwctl`: debugging and automation entry point

### 5.3 Files

- Config (source of truth): `~/.config/project-workspaces/config.toml`
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
  - Accessibility permission is not granted
- If `ide.*.appPath` / `bundleId` are omitted, Doctor must attempt app discovery via Launch Services.
- Doctor must print discovered values as a copy/paste config snippet and must not auto-edit `config.toml`.
- Config parsing must tolerate unknown keys so that unsupported keys can be surfaced as WARN instead of becoming a parse failure (at minimum: tolerate `global.switcherHotkey` so it can be WARNed + ignored).
- If `global.switcherHotkey` is present, Doctor must WARN (“Hotkey is fixed to ⌘⇧Space; key is ignored; remove it.”) and runtime must ignore it.
Defaults (applied if keys are missing):

> **Note:** See `README.md` for the authoritative table of defaults and Doctor severity levels.

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
- Switcher ordering and filtering:
  - Preserve config file order by default.
  - Filter is case-insensitive substring match on project `id` or `name`.
  - After each query change, selection resets to the first match.
  - If there are no matches, show a “No matches” row/label and Enter does nothing.
- Switcher states:
  - **Browsing**: list + search; switcher is key for typing.
  - **Loading(projectId, step)**: switcher remains visible as a HUD but must **not** be key/focused; inputs disabled except Esc after the user re-focuses the switcher via hotkey.
  - **Error(projectId, message)**: switcher is key and shows Retry + Cancel.
- Hotkey behavior:
  - In **Browsing**, ⌘⇧Space dismisses the switcher (same as Esc).
  - In **Loading**, ⌘⇧Space focuses the switcher (does **not** dismiss).
- Activation UX:
  - On Enter, switcher transitions to **Loading**, stays visible, and is forced non-key.
  - Capture the previously focused AeroSpace window (best effort) when opening the switcher:
    - `aerospace list-windows --focused --json --format '%{window-id} %{workspace}'`
    - Store `prevFocusedWindowId` and `prevWorkspaceName` if available.
  - If the switcher exits without selecting a project, restore focus best-effort:
    - If `prevFocusedWindowId` exists: `aerospace focus --window-id <id>`
    - Else if `prevWorkspaceName` exists: `aerospace summon-workspace <name>`
  - On activation success, focus IDE and close switcher.
  - On activation error, switcher becomes key and shows Retry/Cancel.
  - Cancel during Loading stops further launches, closes the switcher, and restores previous focus best-effort; any windows already opened remain open.
- If the hotkey cannot be registered, the menu bar must show a persistent “Hotkey unavailable” warning and provide **Open Switcher...** to access the switcher manually.

**MUST (Close)**

- In switcher, **⌘W** closes the selected project workspace (Close Project).

### PR-020 — Activate(Project) behavior

**MUST**

Given `projectId`:

1) Summon workspace `pw-<projectId>`.
   - `aerospace summon-workspace <workspace>`
   - Confirm focused workspace using `aerospace list-workspaces --focused`.
   - The switcher must remain visible on the target workspace during activation (AppKit-only; no AeroSpace move for the switcher).
2) Load project bindings (IDE + Chrome) and prune stale ones using a read-only window snapshot:
   - `aerospace list-windows --all --json`
   - Stale bindings (missing window id or mismatched bundle id) are removed.
3) Move bound windows to `pw-<projectId>` (only by window id).
4) If a role has no binding after pruning, open a new window for that role and bind it (one per role).
5) Re-confirm focused workspace.
6) Apply canonical layout **only if no bound windows were already on the workspace**:
   - `flatten-workspace-tree --workspace <workspace>`
   - `balance-sizes --workspace <workspace>`
   - `layout --window-id <ideId> h_tiles`
   - Resize IDE width to a deterministic value based on focused monitor visible width.
7) End with IDE focused.

**MUST**

- Activation is CLI-only (no Accessibility geometry).
- All AeroSpace commands execute via a serialized executor.
- Activation fails if workspace focus cannot be confirmed or a required window cannot be opened/detected.
- Activation must fail fast with a compatibility error if required AeroSpace commands are unsupported.
- Stale bindings are pruned and logged; unbound windows are never moved.

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

- Activation uses the project’s bound Chrome window if present.
- If no bound Chrome window exists, activation opens a new Chrome window and binds it (one per role).
- Optional URLs may be opened only when creating a **new** Chrome window; existing Chrome windows/tabs are not mutated.
- Unbound Chrome windows are never moved or resized.

### PR-050 — IDE behavior

**MUST**

- Supported IDEs: VS Code and Antigravity.
- Global default IDE exists with per-project override.
- Activation resolves IDE identity (bundle id + app name) from config and Launch Services.
- Activation uses the project’s bound IDE window if present.
- If no bound IDE window exists, activation opens a new IDE window and binds it (one per role).
- Unbound IDE windows are never moved or resized.

### PR-060 — Canonical layout

**MUST**

- Reset workspace layout **only when the workspace is newly opened** (no bound windows present):
  - `flatten-workspace-tree` then `balance-sizes`
  - `layout h_tiles` anchored on the IDE window
  - resize IDE width to a deterministic value derived from focused monitor visible width
- IDE ends focused.

### PR-070 — Layout persistence

**MUST (current)**

- No explicit layout persistence. If the workspace is already open with bound windows, activation preserves the current layout.

### PR-080 — Diagnostics and repeatability

**MUST**

- Provide `pwctl doctor` and an in-app “Run Doctor.”
- Doctor must validate:
  - Homebrew installed (required for AeroSpace install; manual installs deferred)
  - AeroSpace installed and CLI resolvable (server reachable once safe config is in place)
  - Accessibility permission granted to ProjectWorkspaces
  - Chrome installed
  - VS Code installed (and Antigravity if configured)
  - global hotkey ⌘⇧Space can be registered (FAIL if registration fails due to conflict / OS denial)
  - if the agent app is running, Doctor must use the app-reported hotkey status when available; otherwise skip the hotkey registration check and report PASS with a note that the hotkey is managed by the agent
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
  - `Install AeroSpace`
  - `Install Safe AeroSpace Config`
  - `Start AeroSpace`
- Secondary buttons:
  - `Reload AeroSpace Config`
  - `Emergency: Disable AeroSpace`
  - `Uninstall Safe AeroSpace Config`
  - `Close`

Step 1 — Detect AeroSpace installation

- PASS: `PASS  AeroSpace.app found at: /Applications/AeroSpace.app`
- FAIL: `FAIL  AeroSpace.app not found in /Applications`
  - `Fix: Install AeroSpace via Homebrew (required for now). Then re-run Doctor.`
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
  - `Fix: Run: aerospace summon-workspace <prev>`
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
  - per-command start/end timestamps + durationMs
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

1) **Activate succeeds with required windows**
   - If bound windows exist, Activate(Project) succeeds and ends with IDE focused.
   - If bound windows are missing, activation opens and binds one IDE + one Chrome window.

2) **Activate fails on hard errors**
   - Workspace focus cannot be confirmed, or a required window cannot be opened/detected.

3) **Canonical layout applied**
   - When the workspace is newly opened, activation resets layout to `h_tiles` and sets IDE width to ~60% of visible width (with clamps).

4) **Close empties the workspace**
   - Close(Project) closes every window in that project workspace.

5) **Doctor works**
   - On a fresh macOS machine, following README + Doctor results in a working system.

---

## 9. Future candidates (explicitly not committed)

These are possible later additions but are not part of v1 scope:

- Notifications / attention system
- Gesture invocation
- Support for additional browsers or IDEs
- Workspace templates beyond IDE+Chrome
