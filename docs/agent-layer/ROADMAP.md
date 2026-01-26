# Roadmap

Note: This is an agent-layer memory file. It is primarily for agent use.

## Phases

<!-- PHASES START -->

## Phase 0 ✅ — Project scaffold + contracts + doctor skeleton

- Created Xcode targets: `ProjectWorkspacesApp` (SwiftUI menu bar agent), `ProjectWorkspacesCore` (pure Swift module), `pwctl` (CLI tool).
- Established CLI-driven build workflow via `scripts/dev_bootstrap.sh`, `scripts/build.sh`, `scripts/test.sh` (Xcode GUI optional).
- Implemented TOML config parsing with strict validation, explicit defaults, and tolerant unknown-key handling.
- Implemented `pwctl` command surface: `doctor`, `list`, `activate` (stub), `close` (stub), `logs`.
- Implemented `pwctl doctor` with PASS/FAIL/WARN checks, actionable guidance, and AeroSpace config state handling.
- Added in-app "Run Doctor" action using the same core engine as `pwctl doctor`.
- Implemented structured logging with rotation (10 MiB, 5 archives).
- Added CI workflow and unit tests for config validation, doctor severity, and log rotation.


## Phase 1 — AeroSpace client wrapper + window enumeration primitives

### Goal
- Provide a reliable, testable wrapper around the `aerospace` CLI and window enumeration.

### Tasks
- [x] Resolve the `aerospace` binary path once at startup (no hardcoded PATH assumptions).
- [x] Implement `AeroSpaceClient` command execution with timeouts and structured stdout/stderr capture.
- [x] Decode `aerospace list-windows ... --json` output into typed models.
- [x] Add retry policy for “AeroSpace not ready” failures (max 20 attempts, 50ms initial, 1.5x backoff, 750ms cap, 5s total, +/-20% jitter).
- [x] Add unit tests for AeroSpace JSON decoding and CLI wrapper behavior using fixtures/mocks (CI-required).
- [x] Add opt-in AeroSpace integration tests gated behind `RUN_AEROSPACE_IT=1` (local-only).

### Exit criteria
- When `RUN_AEROSPACE_IT=1`, integration tests can switch workspace, enumerate windows, and focus a window by id.
- AeroSpace command failures produce structured, actionable errors (not silent).


## Phase 2 — VS Code workspace generation + IDE launch pipeline

### Goal
- Make IDE window creation deterministic and ensure stable project identity via VS Code workspace colors.

### Tasks
- [ ] Generate `~/.config/project-workspaces/vscode/<projectId>.code-workspace` with folder + `workbench.colorCustomizations` derived from `project.colorHex`.
- [ ] Implement IDE launch priority: `ideCommand` → agent-layer launcher → `open -a <IDE.appPath> <workspaceFile>`.
- [ ] Install and use a tool-owned `code` shim at `~/.local/share/project-workspaces/bin/code` (avoid requiring `code` in PATH).
- [ ] After custom launches, enforce workspace identity by opening the generated workspace file in reuse-window mode via the VS Code CLI.
- [ ] Add Antigravity support using the same workspace file (CLI optional; fallback to `open -a`).
- [ ] Add unit tests for workspace file contents, `colorHex` validation, and launch selection rules.

### Exit criteria
- Activating a project with no IDE window opens the IDE and applies project color identity.
- `ideCommand` and agent-layer launcher paths work; failures fall back to opening the workspace file directly.


## Phase 3 — Chrome window creation + tab seeding

### Goal
- Ensure exactly one Chrome window exists per project workspace and seed tabs only on creation.

### Tasks
- [ ] When Chrome window is missing, create it with `--new-window` and URLs in this order: `global.globalChromeUrls` → `project.repoUrl` (if set) → `project.chromeUrls`.
- [ ] Detect the newly created Chrome window by diffing `aerospace list-windows --all --json --format '%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title}'` before/after launch.
- [ ] Ensure existing Chrome windows are never mutated (no tab enforcement after creation).
- [ ] Enforce the focus rule: activation ends with the IDE focused (Chrome must not steal focus).
- [ ] Add an automated (or manual, documented) check that Chrome recreation produces the expected tabs.

### Exit criteria
- If the Chrome window is closed, activation recreates it with the expected tabs and ends focused on the IDE.
- If the Chrome window already exists, activation does not modify tabs.


## Phase 4 — Activation engine (Activate(Project))

### Goal
- Implement `Activate(projectId)` end-to-end with idempotence and deterministic window placement.

### Tasks
- [ ] Implement `Activate(projectId)` algorithm: switch to `pw-<projectId>` workspace → enumerate windows → ensure IDE → ensure Chrome → move windows into workspace → float → apply layout → focus IDE.
- [ ] Define and enforce how the "project IDE window" and "project Chrome window" are identified (bundle id / app identity + workspace membership).
- [ ] Ensure activation is idempotent (no duplicate IDE/Chrome windows on repeated runs).
- [ ] Log every activation with timestamp, projectId, workspaceName, AeroSpace command stdout/stderr, and final outcome (success/warn/fail).
- [ ] Add automated coverage for idempotence and missing-window recovery (integration test where feasible).

### Exit criteria
- `pwctl activate <projectId>` is idempotent and always ends with IDE focused.
- Unrecoverable failures (missing project path, missing permissions) fail loudly with actionable errors.


## Phase 5 — Switcher UI + global hotkey

### Goal
- Provide the keyboard-first switcher UX with Activate and Close actions.

### Tasks
- [ ] Implement global hotkey ⌘⇧Space to open the switcher using Carbon `RegisterEventHotKey` (Apple-only; no third-party hotkey libraries).
- [ ] Implement type-to-filter list with color swatch + name; Enter activates; Esc dismisses.
- [ ] Implement Close Project shortcut ⌘W to close the selected project.
- [ ] Ensure the switcher works when invoked from any application (app runs as background agent).

### Exit criteria
- Switcher is usable entirely from the keyboard and reliably invoked from any app.


## Phase 6 — Layout engine + persistence

### Goal
- Apply locked default layouts and persist per-project per-display-mode geometry.

### Tasks
- [ ] Implement display mode detection using main display width and `display.ultrawideMinWidthPx`.
- [ ] Implement locked default layouts for laptop and ultrawide (8-segment split).
- [ ] Implement `state.json` read/write (versioned) as a cache; missing state must be safe and explicit.
- [ ] Persist layout on window move/resize via Accessibility (AX) APIs, debounced 500ms.
- [ ] Apply geometry by focusing the target window via AeroSpace, then mutating the system “focused window” via AX.
- [ ] Add unit tests for layout math and state serialization.

### Exit criteria
- User window moves/resizes persist and are restored on next activation for the same display mode.


## Phase 7 — Close Project (empty the workspace)

### Goal
- Implement aggressive Close semantics that empties the project workspace and provides a safe fallback workspace.

### Tasks
- [ ] Implement `Close(projectId)` algorithm: enumerate windows in `pw-<projectId>` and close each (sorted ascending by id).
- [ ] When closing the focused project workspace, switch to fallback workspace `pw-inbox`.
- [ ] Surface close in both switcher (⌘W) and `pwctl close <projectId>`.
- [ ] Ensure per-window close failures are WARN; overall command fails only on AeroSpace execution failure.
- [ ] Log every close action with timestamp, projectId, workspaceName, AeroSpace command stdout/stderr, and final outcome (success/warn/fail).

### Exit criteria
- Close empties the project workspace and next activation recreates missing windows as needed.


## Phase 8 — Packaging + onboarding + documentation polish

### Goal
- Ship a signed/notarized app with clear onboarding and ensure PRD acceptance criteria are met.

### Tasks
- [ ] Implement signing + notarization for `ProjectWorkspaces.app` and package `pwctl` alongside.
- [ ] Add release scripts: `scripts/archive.sh` (xcodebuild archive/export) and `scripts/notarize.sh` (notarization + stapling) so releases do not require the Xcode GUI.
- [ ] Finalize README: install, permissions, config schema, usage, troubleshooting.
- [ ] Ensure `doctor` covers complete setup (AeroSpace, Accessibility, Chrome, IDEs, config validity, required directories).
- [ ] Run the PRD end-to-end acceptance criteria and document results (manual + automated where feasible).
- [ ] Implement and document distribution via both: Homebrew cask (recommended) and signed+notarized direct download (`.zip` or `.dmg`).

### Exit criteria
- A fresh macOS machine can be set up using README alone and `pwctl doctor` reports no FAIL on a correctly configured system.
- PRD acceptance criteria 1–7 are satisfied.
