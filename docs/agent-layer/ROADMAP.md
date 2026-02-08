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

## Phase 1 ✅ — Foundations: Doctor, config, persistence (UI skeleton)
- Doctor is 100% functional with checks for Homebrew, AeroSpace, VS Code, Chrome, agent-layer CLI, config validity, and directories.
- Config loading/validation is exhaustive with actionable errors; schema documented in README.
- StateStore persistence API implemented with versioned JSON schema, focus stack (LIFO, 20 max, 7-day prune), and lastLaunchedAt.
- CLI has test coverage for argument parsing and command execution; `ap --version` added.
- Core interface document (`docs/CORE_API.md`) catalogs all public APIs.
- Switcher UI skeleton loads config, lists projects, and logs selections.

## Phase 2 ✅ — Focus + switcher UX + core interfaces (separation of concerns)
- Focus domain model defined with FocusEvent, FocusEventKind, and SessionManager as the single source of truth for state and focus history.
- Focus history persisted via StateStore with query, prune, and export capabilities; comprehensive test coverage.
- Switcher search + sorting rules specified and implemented in ProjectSorter: recency-based ordering, prefix-match prioritization, case-insensitive substring matching.
- Strict separation of concerns enforced: business logic in AgentPanelCore, presentation in App/CLI.
- AppKit integration consolidated into shared AgentPanelAppKit module (Core → AppKit → App/CLI layering).

## Phase 3 ✅ — MVP: activation/project lifecycle
- Activation/project lifecycle API designed and implemented in AgentPanelCore with success/failure states and idempotency.
- Activation orchestration implemented with tests for success, failure, and partial-failure scenarios.
- "Close project" implemented in core (API complete; UI wiring deferred to Phase 4).
- "Exit to previous window" implemented — returns focus to last non-project window.
- Switcher wired to activation with progress and failure messaging.
- Public API audit: CLI-only items removed; 20+ internal types made internal; CORE_API.md updated.

## Phase 4 — UX polish

### Goal
- Polish the user experience for project lifecycle, making close/switch workflows smooth and adding visual feedback.
- Wire remaining core capabilities (close project, return to non-project window) into the UI.

### Tasks
- [x] Wire "close project" to the UI; closing a project returns the user to the most recent non-project window.
- [x] Add keybind to toggle back to most recent macOS space or non-project window.
- [x] Visual health indicator in AP menu bar icon — icon state reflects Doctor results (e.g., red for errors, yellow for warnings).
- [ ] Add dropdown menu item to move the currently focused window to any of the open project's workspaces. The top level menu item would be Add Window to Project -> [Project 1, Project 2, Project 3]

### Exit criteria
- Users can close a project from the UI and are returned to a non-project context.
- A keybind reliably toggles focus back to the previous space or non-project window.
- Visual feedback (loader, health icon) is present and accurate during startup and after Doctor runs.

## Phase 5 — Release: agent-layer support, packaging, tests, documentation

### Goal
- Support agent-layer end-to-end, including Doctor checks and onboarding when required.
- Ship a release-quality build with deterministic install/upgrade via Homebrew (per current decisions).
- Ensure tests, docs, and onboarding are polished enough for first external users.

### Tasks
- [ ] Ensure agent-layer is supported: if `useAgentLayer = true`, Doctor verifies it is installed/usable; if missing, route users to onboarding instead of dead ends.
- [ ] Decide distribution shape: Homebrew cask/app + formula/CLI (or a single package) and document it in README.
- [ ] Implement signing + notarization for `AgentPanel.app` and integrate it into scripted releases (no manual Xcode GUI steps).
- [ ] Add release scripts (e.g., `scripts/archive.sh`, `scripts/notarize.sh`, and a one-command `scripts/release.sh`) for archive/export/notarize/staple.
- [ ] Finalize README: install (Homebrew), permissions, config schema, usage (switcher + `ap`), troubleshooting.
- [ ] Add CI gates (build + tests) and a documented release checklist.
- [ ] Validate onboarding on a fresh machine using README + Doctor only (no tribal knowledge).

### Exit criteria
- If a project requires agent-layer and it is missing, onboarding can install/enable it and Doctor passes afterwards.
- A release can be produced via scripts and installed via Homebrew; upgrades are deterministic.
- A fresh macOS machine can be set up using README alone; Doctor reports no FAIL on a correctly configured system.
- CI is green and a release checklist exists.

## Phase 6 — Future: UX + extensibility

### Goal
- Implement post-MVP user-facing features and extensibility improvements.

### Tasks
- [ ] Auto-start at login (opt-in) and optional "restore last project" behavior.
- [ ] Fuzzy search with ranking in the switcher.
- [ ] Favorites/stars for projects (persisted) and UI affordances.
- [ ] Add project flow in the UI (including "+" button) that writes to config safely.
- [ ] Add/edit projects in a GUI (all config options in form).
- [ ] Custom IDE support: config `[[ide]]` blocks (app path, bundle id, etc) and project `ide = "vscode" | "<custom>"`.
- [ ] Better integration with existing AeroSpace config (non-destructive merge; avoid overwriting).
- [ ] Optional: direct-download distribution (`.zip`/`.dmg`) if/when we revisit the Homebrew-only install decision.

### Exit criteria
- Phase 6 is split into one or more concrete follow-on phases with scoped goals; any remaining work is tracked in BACKLOG.md.
