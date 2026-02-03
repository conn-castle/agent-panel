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

## Phase 0 ✅ — AgentPanel reset and cleanup
- Renamed the app/core targets to AgentPanel and removed the legacy CLI.
- Stripped activation/workspace management from the switcher, leaving list + selection logging.
- Updated paths, logging, and docs to the AgentPanel namespace.

## Phase 1 — Foundations: Doctor, config, persistence (UI skeleton)

### Goal
- Keep the UI intentionally skeletal while making Doctor and project config production-grade.
- Define canonical persistence (logs + state/history) with detailed, structured logging.
- Fully cover first-run onboarding and install checks (including Homebrew-only assumptions).

### Tasks
- [x] Define and document the canonical on-disk layout (config, logs, state/history) in a prose doc, not just code.
- [x] Document the config TOML schema formally (fields, types, defaults, validation rules).
- [x] Make config loading/validation exhaustive and consistent across app + CLI (no hidden defaults; actionable errors).
- [x] Make Doctor "100% functional": full check suite for config validity, required directories, Homebrew, AeroSpace (app + CLI), Chrome, supported IDEs, and any agent-layer prerequisites.
- [ ] Define a persistence API in `AgentPanelCore` (e.g., a `StateStore`) and implement it (incl. migrations/versioning strategy) with structured logs.
- [ ] Add CLI tests: argument parsing, command execution, error handling.
- [x] Add `ap --version` command and ensure version is reported consistently (CLI, app, Doctor).
- [ ] Write a "core interface document" defining `AgentPanelCore` public API boundaries (moved from Phase 2).
- [x] Keep the switcher UI as a skeleton: load config, list projects, basic filter, and log selections with stable identifiers.
- [x] Ensure `ap doctor` and in-app Doctor share the same core report types/output and remain end-to-end working (`scripts/test.sh` stays green).

### Exit criteria
- `ap doctor` and the in-app Doctor produce a complete report with clear PASS/WARN/FAIL and actionable remediation steps. ✅
- Config can be created/loaded/validated deterministically; invalid configs fail loudly with specific messages. ✅
- A real state store exists on disk (with a documented schema + versioning) and is exercised by at least one persisted datum.
- CLI has test coverage for argument parsing and core commands.
- Core interface document exists and matches implemented public APIs.
- On-disk layout and config schema are documented. ✅
- `ap --version` reports version consistently with Doctor output. ✅
- AgentPanel launches and the switcher skeleton works; `scripts/test.sh` passes. ✅

## Phase 2 — Focus + switcher UX + core interfaces (separation of concerns)

### Goal
- Define focus functionality and persist focus history.
- Specify and implement project searching/sorting/selecting behavior in the switcher UI.
- Publish a clear, stable interface for core functionality so App/CLI remain thin presentation layers.

### Tasks
- [ ] Define and enforce the target boundaries for `AgentPanelApp` vs `AgentPanelCore` vs `AgentPanelCLI`; delete/merge anything that doesn't fit.
- [ ] Define the Focus domain model and events in `AgentPanelCore` (UTC timestamps; stable ids).
- [ ] Implement focus history storage on the Phase 1 persistence substrate (query, prune/export) with tests.
- [ ] Specify and implement switcher search + sorting rules (including whether focus history influences ordering) with tests.
- [ ] Refactor for strict separation of concerns: move business rules out of UI targets into `AgentPanelCore`.
- [ ] Revisit AppKit integration: attempt a single shared AppKitIntegration module usable by both App and CLI (without importing AppKit from `AgentPanelCore`), or reaffirm the duplication with an updated decision.

### Exit criteria
- Focus history is persisted and retrievable; tests cover storage and ordering rules.
- Switcher supports search/sort/select per spec and remains presentation-only.
- AppKit integration approach is settled and documented (shared module or intentional duplication).

## Phase 3 — MVP: activation/project lifecycle + agent-layer support

### Goal
- Implement actual AgentPanel logic with a small, stable interface for selecting and switching projects.
- Support agent-layer end-to-end, including Doctor checks and onboarding when required.
- Support closing a project; reach MVP state.

### Tasks
- [ ] Design the activation/project lifecycle API surface in `AgentPanelCore` (success/failure states, idempotency, logging).
- [ ] Implement activation orchestration with tests for success/failure scenarios (including partial failures and cleanup).
- [ ] Implement “close project” in core and wire it to `ap` + UI, with tests.
- [ ] Wire switcher selection to activation and update UI messaging (progress + failures).
- [ ] Ensure agent-layer is supported: if `useAgentLayer = true`, Doctor verifies it is installed/usable; if missing, route users to onboarding instead of dead ends.

### Exit criteria
- Selecting a project reliably activates it; closing a project reliably returns to a neutral state.
- If a project requires agent-layer and it is missing, onboarding can install/enable it and Doctor passes afterwards.
- CLI and app share the same core lifecycle implementation; `scripts/test.sh` passes.

## Phase 4 — Release: packaging, tests, documentation

### Goal
- Ship a release-quality build with deterministic install/upgrade via Homebrew (per current decisions).
- Ensure tests, docs, and onboarding are polished enough for first external users.

### Tasks
- [ ] Decide distribution shape: Homebrew cask/app + formula/CLI (or a single package) and document it in README.
- [ ] Implement signing + notarization for `AgentPanel.app` and integrate it into scripted releases (no manual Xcode GUI steps).
- [ ] Add release scripts (e.g., `scripts/archive.sh`, `scripts/notarize.sh`, and a one-command `scripts/release.sh`) for archive/export/notarize/staple.
- [ ] Finalize README: install (Homebrew), permissions, config schema, usage (switcher + `ap`), troubleshooting.
- [ ] Add CI gates (build + tests) and a documented release checklist.
- [ ] Validate onboarding on a fresh machine using README + Doctor only (no tribal knowledge).

### Exit criteria
- A release can be produced via scripts and installed via Homebrew; upgrades are deterministic.
- A fresh macOS machine can be set up using README alone; Doctor reports no FAIL on a correctly configured system.
- CI is green and a release checklist exists.

## Phase 5 — Future: UX + extensibility

### Goal
- Implement post-MVP user-facing features and extensibility improvements.

### Tasks
- [ ] Auto-start at login (opt-in) and optional “restore last project” behavior.
- [ ] Fuzzy search with ranking in the switcher.
- [ ] Favorites/stars for projects (persisted) and UI affordances.
- [ ] Add project flow in the UI (including “+” button) that writes to config safely.
- [ ] Add/edit projects in a GUI (all config options in form).
- [ ] Custom IDE support: config `[[ide]]` blocks (app path, bundle id, etc) and project `ide = "vscode" | "<custom>"`.
- [ ] Better integration with existing AeroSpace config (non-destructive merge; avoid overwriting).
- [ ] Optional: direct-download distribution (`.zip`/`.dmg`) if/when we revisit the Homebrew-only install decision.

### Exit criteria
- Phase 5 is split into one or more concrete follow-on phases with scoped goals; any remaining work is tracked in BACKLOG.md.
