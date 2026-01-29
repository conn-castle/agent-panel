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


## Phase 1 ✅ — AeroSpace client wrapper + window enumeration primitives

- Implemented `AeroSpaceClient` with command execution, timeouts, and structured stdout/stderr capture.
- Resolved `aerospace` binary path once at startup (no hardcoded PATH assumptions).
- Decoded `aerospace list-windows --json` output into typed `AeroSpaceWindow` models.
- Added retry policy for "AeroSpace not ready" failures (max 20 attempts, 50ms initial, 1.5x backoff, 750ms cap, 5s total, ±20% jitter).
- Added unit tests for JSON decoding and CLI wrapper behavior using fixtures/mocks (CI-required).
- Added opt-in AeroSpace integration tests gated behind `RUN_AEROSPACE_IT=1` (local-only).


## Phase 2 ✅ — VS Code workspace generation + IDE launch pipeline

- Generated `.code-workspace` files with `workbench.colorCustomizations` derived from `project.colorHex`.
- Implemented IDE launch pipeline (ideCommand/launcher/open fallback), VS Code CLI enforcement via shim, and Antigravity open fallback.
- Added unit tests for workspace generation, color palette validation, environment building, and launch selection rules.


## Phase 3 ✅ — Chrome window creation + tab seeding

- Implemented `ChromeLauncher` with workspace precondition enforcement and deterministic window detection.
- Created Chrome windows with `--new-window` and ordered, deduplicated URLs (`globalChromeUrls` → `repoUrl` → `chromeUrls`).
- Detected newly created Chrome windows by diffing AeroSpace window IDs before/after launch with fixed polling.
- Handled edge cases: existing windows (single/multiple), ambiguous detection within the workspace, and timeout errors without cross-workspace scanning.
- Enforced IDE refocus after Chrome creation via `refocusIdeWindow` helper.
- Added `.unexpectedOutput` error case to `AeroSpaceCommandError` for semantic precision.
- Extracted shared test helpers (`AeroSpaceCommandSignature`, `SequencedAeroSpaceCommandRunner`) to reduce duplication.
- Added 11 unit tests covering all Chrome launcher scenarios.


## Phase 4 ✅ — Activation engine (Activate(Project))
- Implemented no-hijack activation that is idempotent, deterministic, and leaves the IDE focused.
- Added structured activation logging with AeroSpace command capture and explicit warning/error outcomes.
- Added unit coverage for idempotence, missing-window recovery, and edge cases in activation orchestration.


## Phase 5 ✅ — Switcher UI + global hotkey

- Implemented global hotkey ⌘⇧Space using Carbon `RegisterEventHotKey` (Apple-only; no third-party hotkey libraries).
- Implemented type-to-filter switcher list with color swatch + name; Enter activates; Esc dismisses.
- Switcher works when invoked from any application (app runs as background agent).


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
- [ ] Implement Close Project shortcut ⌘W to close the selected project.
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
