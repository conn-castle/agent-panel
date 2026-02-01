# Roadmap

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
A phased plan of work that guides architecture decisions and sequencing. The roadmap is the “what next” reference; the backlog holds unscheduled items.

## Format
- The roadmap is a single list of numbered phases under `<!-- PHASES START -->`.
- Do not renumber completed phases (phases marked with ✅).
- You may renumber incomplete phases when updating the roadmap (e.g., to insert a new phase).
- Incomplete phases include **Goal**, **Tasks** (checkbox list), and **Exit criteria** sections.
- When a phase is complete:
  - update the heading to: `## Phase N ✅ — <phase name>`
  - replace the phase content with a short bullet summary of what was accomplished (no checkbox list).

### Phase templates

Completed:
```markdown
## Phase N ✅ — <phase name>
- <Accomplishment summary bullet>
- <Accomplishment summary bullet>
```

Incomplete:
```markdown
## Phase N — <phase name>

### Goal
- <What success looks like for this phase, in 1–3 bullet points.>

### Tasks
- [ ] <Concrete deliverable-oriented task>
- [ ] <Concrete deliverable-oriented task>

### Exit criteria
- <Objective condition that must be true to call the phase complete.>
- <Prefer testable statements: “X exists”, “Y passes”, “Z is documented”.>
```

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

- Generated IDE workspace files with `workbench.colorCustomizations` derived from `project.colorHex`.
- Implemented IDE launch pipeline and workspace generation (legacy pipeline later removed; minimal auto-open + workspace generation reintroduced in the 2026-02 binding-based activation).
- Added unit tests for workspace generation, color palette validation, environment building, and launch selection rules.
- Superseded by the 2026-02 CLI-only activation migration; legacy IDE launch automation was removed.


## Phase 3 ✅ — Chrome window creation + tab seeding

- Implemented `ChromeLauncher` with workspace precondition enforcement and deterministic window detection.
- Created Chrome windows with ordered, deduplicated URLs (legacy Chrome automation; minimal `open -na` remains in binding-based activation for missing windows).
- Detected newly created Chrome windows by diffing AeroSpace window IDs before/after launch with fixed polling.
- Handled edge cases: existing windows (single/multiple), ambiguous detection within the workspace, and timeout errors without cross-workspace scanning.
- Enforced IDE refocus after Chrome creation via `refocusIdeWindow` helper.
- Added `.unexpectedOutput` error case to `AeroSpaceCommandError` for semantic precision.
- Extracted shared test helpers (`AeroSpaceCommandSignature`, `SequencedAeroSpaceCommandRunner`) to reduce duplication.
- Added 11 unit tests covering all Chrome launcher scenarios.
- Superseded by the 2026-02 CLI-only activation migration; Chrome launch automation was removed.


## Phase 4 ✅ — Activation engine (Activate(Project))
- Implemented no-hijack activation that is idempotent, deterministic, and leaves the IDE focused.
- Added structured activation logging with AeroSpace command capture and explicit warning/error outcomes.
- Added unit coverage for idempotence, missing-window recovery, and edge cases in activation orchestration.
 - Added binding-based activation that opens and binds a single IDE + Chrome window when missing and leaves unbound windows untouched.


## Phase 5 ✅ — Switcher UI + global hotkey

- Implemented global hotkey ⌘⇧Space using Carbon `RegisterEventHotKey` (Apple-only; no third-party hotkey libraries).
- Implemented type-to-filter switcher list with color swatch + name; Enter activates; Esc dismisses.
- Switcher works when invoked from any application (app runs as background agent).


## Phase 6 ✅ — Layout engine + persistence
- Implemented display mode detection for laptop and ultrawide modes.
- Implemented default layouts (maximized for laptop, 8-segment split for ultrawide).
- Implemented versioned layout state cache for layout persistence with atomic writes.
- Persisted geometry on window move/resize via Accessibility (AX) APIs with 500ms debounce.
- Applied geometry via AeroSpace window focus and AX focused-window mutation.
- Added unit tests for layout math and state serialization.
- Superseded by the 2026-02 CLI-only activation migration; AX-based layout persistence was removed.

## Phase 7 ✅ — Architecture cleanup + Core/App boundary
- Introduced the Core workspace facade (`WorkspaceManaging`) and focus snapshot/restore in Core so the App no longer touches AeroSpace internals.
- Refactored ActivationService into step-based orchestration with shared window-detection configuration and StateStoring test doubles.
- Unified command execution/error handling (ProcessRunner + CommandExecutionError) and extracted named switcher timing constants.

## Phase 8 — Stability refactors for activation, Chrome, and switcher

### Goal
- Reduce duplication and shrink the remaining monoliths without changing user-facing behavior.
- Make switcher state transitions explicit and easier to test.

### Tasks
- [ ] Extract ActivationService steps into named types or methods and move step implementations into dedicated files.
- [ ] Replace SwitcherPanelController’s implicit state machine with explicit state structs/reducer-style updates.

### Exit criteria
- ActivationService is a small orchestrator (target under ~300 lines) with steps in separate files.
- SwitcherPanelController state transitions are explicit and covered by updated tests.

## Phase 9 — Close Project (empty the workspace)

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
- Close empties the project workspace; activation reopens/binds IDE and Chrome windows as needed.


## Phase 10 — Packaging + onboarding + documentation polish

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
