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

## Phase 4 ✅ — UX polish
- Wired "close project" into the UI and restored users to non-project context on close.
- Added keybind behavior to toggle back to the most recent macOS space or non-project window.
- Added visual menu bar health indication driven by Doctor results.

## Phase 5 ✅ — Daily-driver required features
- Chrome tab persistence: Verbatim URL capture and restoration via AppleScript.
- LIFO Focus Stack: Returns to last non-project window with workspace-level fallbacks when the stack is exhausted.
- SSH & Agent Layer Support: Orchestration for `code --remote` and `al sync` with environment preservation and `.vscode/settings.json` tagging for window identification.
- Config Hardening: Strict absolute path validation and protection against malicious SSH authority options.
- PATH Propagation: Robust PATH discovery via login shell with timeout and pipe safety.
- Switcher UX Polish: Automatic focus refresh on project close to ensure reliable restoration and subsequent selections.
- Core Extensibility: Added `workingDirectory` support to the `CommandRunning` interface.

## Phase 6 — Cleanup: reduce code debt + raise coverage

### Goal
- Reduce high-risk code debt and regressions by addressing prioritized issues before building more features.
- Establish and enforce a test coverage bar (> 90%) with repeatable tooling.
- Keep docs and internal APIs consistent as we refactor.

### Tasks
- [x] In the menu, add a view config file option, which will open the Files app to the config file's location for easy access. (`view-config-file`).
- [x] Fix light mode coloring. Currently the switcher only looks good in dark mode.
- [ ] Window rescue for floating IDE/app windows: keep the “all windows floating” AeroSpace strategy, but when AgentPanel focuses/activates a project (and when restoring focus via `ap return` / close / exit), detect if the target VS Code (and optionally Chrome) window is mostly off-screen (e.g., only a 1px slice visible due to stale saved coordinates after monitor/Space changes) and automatically reposition it into a visible `NSScreen.visibleFrame` (clamp/center with padding; do not change tiling/layout). Implement via macOS Accessibility window frame control (AX position/size), map AeroSpace `window-id` to the corresponding AX window reliably, fail loudly with a clear error when Accessibility permission is missing, add a Doctor check + remediation guidance for the required permission, add unit tests for the geometry logic + integration tests covering activation/return/close paths, and document the behavior + permission requirement in README (`offscreen-window-rescue`).
- [x] Fix activation errors invisible when the panel dismisses during async launch (`activation-error-invisible`).
- [x] Add switcher dismiss/restore lifecycle tests (`switcher-lifecycle-tests`).
- [x] Expand ProjectManager tests for config load/sort/recency + full activation path (`pm-tests`).
- [x] Add CLI runner tests for new ProjectManager-backed commands (`cli-runner-tests`).
- [x] Doctor: fail on unrecognized `config.toml` entries (`doctor-unrecognized-config`).
- [x] Doctor: VS Code/Chrome checks should FAIL when a project needs them (`doctorsev`).
- [x] Config: surface config warnings to UI (and/or CLI) (`config-warn`).
- [x] Doctor: restore previous focus when Doctor window closes (`doctor-focus`).
- [x] IDE: replace workspace-based VS Code configuration with a settings.json block (`vscode-settings-json`).
- [x] Add a first-class coverage command/script and document it in COMMANDS.md.
- [x] Enforce > 90% test coverage as a hard gate in `scripts/test.sh`, CI, and a repo-managed git pre-commit hook.
- [x] Raise test coverage to > 90% (as measured by the gate) by adding tests and refactoring for testability. (Hit 95.02% total selected on 2026-02-10.)

### Exit criteria
- All issues referenced in this phase are fixed and removed from ISSUES.md.
- Overall test coverage is > 90% (measured by a documented command in COMMANDS.md).
- `scripts/test.sh` passes.
- Any affected Markdown docs are updated and accurate (README, CORE_API.md, agent-layer docs).

## Phase 7 — Extra non-required features

### Goal
- Deliver optional UX enhancements that improve convenience but are not required for daily-driver readiness.

### Tasks
- [ ] Significantly improve performance of the switcher. Loading and selection should be made as fast as possible.
- [ ] Add dropdown menu item to move the currently focused window to any of the open project's workspaces. The top level menu item would be Add Window to Project -> [Project 1, Project 2, Project 3]
- [ ] Favorites/stars for projects (persisted) and UI affordances. Add the ability to open all favorited projects.
- [ ] Fuzzy search with ranking in the switcher.
- [ ] Auto-start at login (opt-in).
- [ ] Automatically run Doctor on operational errors (for example project startup failure or command failure), either in the background or by surfacing a diagnostic report.
- [ ] Add a setting/command to hide the AeroSpace menu bar icon while preserving AeroSpace window-management behavior (investigate headless/hidden-icon support).
- [ ] Add Chrome visual differentiation that matches the associated VS Code project color/theme (for example via profile customization or theme injection, using VSCodeColorPalette guidance as needed). Also, need to actually set VS Code project color, since that's not done today.
- [ ] Migrate build/test/clean workflow from shell scripts to a Makefile. The Makefile becomes the single entrypoint for all dev operations (`make build`, `make test`, `make clean`, `make coverage`, etc.), calling existing shell scripts where appropriate. `make test` runs tests without code coverage for fast local iteration (~15s savings). `make coverage` runs tests with coverage enabled, enforces the coverage gate, and prints a per-file coverage summary showing covered vs uncovered files. CI uses `make coverage` as its gate. Update COMMANDS.md, README, and git hooks accordingly.

### Exit criteria
- Optional UX features are implemented without regressing required daily-driver workflows.
- Operational failures trigger automatic diagnostics in a predictable, documented way.
- AeroSpace icon visibility can be configured without disabling functional behavior.
- Chrome/VS Code visual correlation is present for projects where the feature is enabled.
- Behavior and limitations are documented where needed.
- New behavior is covered by tests.

## Phase 8 — Release: packaging, verification, and documentation

### Goal
- Ship a release-quality build with deterministic install/upgrade and scripted release steps.
- Finalize release readiness across packaging, CI gates, and onboarding documentation.

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

## Phase 9 — Future post-release features

### Goal
- Track larger post-release product features that are intentionally deferred until after release.

### Tasks
- [ ] Allow Switcher usage when `config.toml` is missing by providing an "Open Project..." flow that adds the selected folder to config and activates it, while preserving config ordering rules and reporting failures clearly.
- [ ] Open project workspaces on dedicated macOS Spaces with a defined strategy (one space per workspace vs all project workspaces on a single dedicated space), and make the selected behavior reliable.
- [ ] Add project flow in the UI (including "+" button) that writes to config safely. Done using a GUI form, auto detect based on path, etc.
- [ ] Custom IDE support: config `[[ide]]` blocks (app path, bundle id, etc) and project `ide = "vscode" | "<custom>"`.
- [ ] Better integration with existing AeroSpace config (non-destructive merge; avoid overwriting).

### Exit criteria
- Missing-config onboarding path allows users to add and open a project from Switcher with explicit error surfacing and no silent defaults.
- Dedicated-space behavior is deterministic and matches the selected configuration strategy.
- Phase 9 is split into one or more concrete follow-on phases with scoped goals; any remaining work is tracked in BACKLOG.md.
