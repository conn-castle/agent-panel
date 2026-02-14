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

## Phase 6 ✅ — Cleanup: reduce code debt + raise coverage
- View Config File menu item, light mode fix, dismiss policy extraction, config warnings surfacing.
- Activation error visibility fix (isActivating guard suppresses premature dismiss during async launch).
- Comprehensive test expansion: switcher dismiss/restore lifecycle, ProjectManager config/sort/recency/activation, CLI runner tests.
- Doctor hardening: unrecognized config keys → FAIL, VS Code/Chrome severity context-aware, focus restore on Doctor window close.
- VS Code settings.json block injection replacing workspace files (local + SSH), proactive write on config load.
- Coverage gate (> 90%) enforced via `scripts/test.sh` + `scripts/coverage_gate.sh` + git pre-commit hook. Hit 95% coverage.

## Phase 7 — Polish required features + harden daily use

### Goal
- Add polish and hardening to existing daily-driver features: better error recovery, visual differentiation, streamlined developer workflow, and quality-of-life improvements.
- Keep the build/test pipeline fast and reliable.

### Tasks
- [ ] Definitively fix light mode in the UI
- [ ] Auto-start at login (opt-in) (`auto-start`).
- [x] Add dropdown menu item to move the currently focused window to any of the open project's workspaces. The top level menu item would be Add Window to Project -> [Project 1, Project 2, Project 3] (`add-window-to-project`).
- [x] Recover Agent Panel: menu item (visible only in `ap-*` workspace) that shrinks oversized windows to fit the screen and centers them, restoring original focus (`recover-agent-panel`).
- [x] Recover All Windows: menu item that moves all windows from all workspaces to workspace "1", shrinks/centers each, shows progress UI, and restores original state (`recover-all-windows`).
- [ ] Automatically run Doctor on operational errors (for example project startup failure or command failure) in the background without lagging the app, surfacing a diagnostic report when relevant (`auto-doctor`).
- [ ] Add Chrome visual differentiation that matches the associated VS Code project color/theme (for example via profile customization or theme injection, using VSCodeColorPalette guidance as needed). Also, need to actually set VS Code project color, since that's not done today (`chrome-vscode-color`).
- [x] Window layout engine: detect screen mode (small vs wide based on physical monitor width via `CGDisplayScreenSize`), calculate default window positions using configurable layout parameters, position IDE and Chrome windows via macOS Accessibility APIs (`AXUIElement` position/size), handle off-screen rescue (shrink and center oversized windows), map AeroSpace `window-id` to AX window by PID + title. Add `[layout]` config section with: `smallScreenThreshold` (inches, default 24), `windowHeight` (% of screen, default 90), `maxWindowWidth` (inches, default 18), `idePosition` (left/right, default left), `justification` (left/right, default right), `maxGap` (% of screen width, default 10). Add Doctor check for Accessibility permission with remediation guidance. Integrate with activation flow (position after focus). Small screen mode = maximized to `NSScreen.visibleFrame`. Wide screen mode = side-by-side with configurable height, width cap, justification, and gap (`window-layout`).
- [x] Window position history: persist last window frame (origin + size) per project per screen mode (small/wide) in a JSON file under `~/.local/state/agent-panel/window-layouts/`. Capture positions via AX on project close/deactivate. On activation, restore saved positions if available; fall back to layout engine defaults if not. If a restored window exceeds the current monitor bounds, shrink to fit and center. History is keyed by `projectId` and `screenMode` (`window-history`).

### Exit criteria
- All tasks are implemented, tested, and documented.
- Auto-doctor runs in the background on operational errors without blocking the main thread or lagging the app.
- Chrome/VS Code visual correlation is present for projects where the feature is enabled.
- Window layout positions IDE and Chrome correctly in both small and wide screen modes on activation.
- Window position history restores saved frames per project per screen mode; oversized windows are clamped.
- Doctor checks for Accessibility permission and provides remediation guidance.
- `[layout]` config section is documented in README with all configurable parameters and defaults.

## Phase 8 — Extra non-required features

### Goal
- Deliver optional UX enhancements that improve convenience but are not required for daily-driver readiness.

### Tasks
- [ ] Significantly improve performance of the switcher. Loading and selection should be made as fast as possible.
- [ ] Favorites/stars for projects (persisted) and UI affordances. Add the ability to open all favorited projects.
- [ ] Fuzzy search with ranking in the switcher.
- [ ] Add a setting/command to hide the AeroSpace menu bar icon while preserving AeroSpace window-management behavior (investigate headless/hidden-icon support).
- [ ] Migrate build/test/clean workflow from shell scripts to a Makefile. The Makefile becomes the single entrypoint for all dev operations (`make build`, `make test`, `make clean`, `make coverage`, etc.), calling existing shell scripts where appropriate. `make test` runs tests without code coverage for fast local iteration (~15s savings). `make coverage` runs tests with coverage enabled, enforces the coverage gate, and prints a per-file coverage summary showing covered vs uncovered files. CI uses `make coverage` as its gate. Update COMMANDS.md, README, and git hooks accordingly (`makefile`).

### Exit criteria
- `make test` and `make coverage` work correctly; CI uses `make coverage` as its gate.
- Optional UX features are implemented without regressing required daily-driver workflows.
- AeroSpace icon visibility can be configured without disabling functional behavior.
- Behavior and limitations are documented where needed.
- New behavior is covered by tests.

## Phase 9 — Release: packaging, verification, and documentation

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

## Phase 10 — Future post-release features

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
- Phase 10 is split into one or more concrete follow-on phases with scoped goals; any remaining work is tracked in BACKLOG.md.
