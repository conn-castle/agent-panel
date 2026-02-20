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
- VS Code settings.json block injection replacing workspace files (local + SSH), reactive write on config change.
- Coverage gate (> 90%) enforced via `scripts/test.sh` + `scripts/coverage_gate.sh` + git pre-commit hook. Hit 95% coverage.

## Phase 7 ✅ — Polish required features + harden daily use
- Window positioning: layout engine with `[layout]` config, AX-based positioning, per-project per-mode persistence, Accessibility permission check in Doctor.
- Window recovery and management: "Move Current Window", "Recover Project" / "Recover All Windows" menu items.
- Workspace cycling: native Swift Option-Tab / Option-Shift-Tab via `WindowCycler` + Carbon hotkeys.
- AeroSpace resilience: circuit breaker (30s cooldown), auto-recovery on crash (max 2 attempts), managed config with versioned templates and user sections.
- UX: auto-start at login, auto-doctor on critical errors, VS Code Peacock color differentiation, Doctor SSH parallelization.

## Phase 8 ✅ — Release: packaging, verification, and documentation
- Distribution shape decided: signed + notarized arm64 assets via GitHub tagged releases (Homebrew deferred).
- Signing + notarization integrated into scripted releases (no manual Xcode GUI steps).
- Release scripts: `ci_archive.sh`, `ci_package.sh`, `ci_notarize.sh`, `ci_release_validate.sh`, `ci_setup_signing.sh`.
- README finalized: install (GitHub Releases), permissions, config schema, usage (switcher + `ap`), troubleshooting.
- CI gates (build + tests) and documented release checklist.
- Fresh-machine onboarding validated using README + Doctor only.

## Phase 9 — Extra non-required features

### Goal
- Deliver optional UX enhancements that improve convenience but are not required for daily-driver readiness.

### Tasks
- [ ] Significantly improve performance of the switcher. Loading and selection should be made as fast as possible.
- [ ] Favorites/stars for projects (persisted) and UI affordances. Add the ability to open all favorited projects.
- [ ] Fuzzy search with ranking in the switcher, including trigram matching as well.
- [ ] Add a setting/command to hide the AeroSpace menu bar icon while preserving AeroSpace window-management behavior (investigate headless/hidden-icon support).
- [x] Migrate build/test/clean workflow from shell scripts to a Makefile. The Makefile becomes the single entrypoint for all dev operations (`make build`, `make test`, `make clean`, `make coverage`, etc.), calling existing shell scripts where appropriate. `make test` runs tests without code coverage for fast local iteration (~15s savings). `make coverage` runs tests with coverage enabled, enforces the coverage gate, and prints a per-file coverage summary showing covered vs uncovered files. CI uses `make coverage` as its gate. Update COMMANDS.md, README, and git hooks accordingly (`makefile`).
- [ ] UI overlay for project window cycling (Option-Tab): Add a UI overlay that shows available windows when cycling with Option-Tab, similar to the macOS Command-Tab switcher. Pressing and holding Option while Tabbing displays a UI panel with window icons/titles; releasing Option selects the highlighted window. Builds on existing `WindowCycler` + Carbon hotkey infrastructure.
- [x] Show remote icon for SSH projects in switcher: Display a visual indicator (e.g., a small remote/cloud icon) next to SSH remote projects in the switcher panel so they are immediately distinguishable from local projects. Projects with a `remote` field in config show a remote indicator in the switcher row; local projects do not. `ProjectConfig.isSSH` already exists; implementation is presentation-only in `SwitcherViews.swift`.

### Exit criteria
- `make test` and `make coverage` work correctly; CI uses `make coverage` as its gate.
- Optional UX features are implemented without regressing required daily-driver workflows.
- AeroSpace icon visibility can be configured without disabling functional behavior.
- Window cycling UI overlay shows available windows during Option-Tab cycling.
- SSH projects are visually distinguishable from local projects in the switcher.
- Behavior and limitations are documented where needed.
- New behavior is covered by tests.

## Phase 10 — Future features

### Goal
- Track larger post-release product features that are intentionally deferred until after release.

### Tasks
- [ ] Allow Switcher usage when `config.toml` is missing by providing an "Open Project..." flow that adds the selected folder to config and activates it, while preserving config ordering rules and reporting failures clearly.
- [ ] Open project workspaces on dedicated macOS Spaces with a defined strategy (one space per workspace vs all project workspaces on a single dedicated space), and make the selected behavior reliable.
- [ ] Add project flow in the UI (including "+" button) that writes to config safely. Done using a GUI form, auto detect based on path, etc.
- [ ] Custom IDE support: config `[[ide]]` blocks (app path, bundle id, etc) and project `ide = "vscode" | "<custom>"`.
- [ ] Better integration with existing AeroSpace config (non-destructive merge; avoid overwriting).
- [ ] Chrome profile selection in config: Implement support for selecting specific Chrome profiles via config.toml (`chromeProfile` key or similar). This allows different projects to open in their respective Chrome profiles, maintaining separation of state and accounts. Chrome windows for a project open using the profile specified in the project's configuration. May involve using `--profile-directory` or similar Chrome CLI flags.
- [ ] Auto-associate existing Chrome window in project workspace: If a project lacks an associated Chrome window but a window is found within the project's workspace (e.g., without matching title), associate it instead of opening a new one. Selecting a project without a matched Chrome window automatically adopts an existing Chrome window if it's already on the project's assigned workspace/screen. Improves seamlessness when switching projects where Chrome windows might have lost their specific title match but are still in the right place.
- [ ] Chrome visual differentiation matching VS Code project color: Apply project color to the Chrome window to visually match the associated VS Code window. Possible approaches: Chrome profile customization, theme injection, or Chrome extension. Deferred from Phase 7 — Chrome has no clean programmatic injection point for color theming (unlike VS Code's Peacock extension). May require a custom Chrome extension or Chrome profile switching.
- [ ] Hot Corners and trackpad activation/switching: Add support for Hot Corners and trackpad gestures (e.g., specific swipes) to trigger the project switcher or quickly toggle between recent projects. Streamlines navigation for laptop users who prefer gesture-based interaction over keyboard shortcuts. User can configure a specific screen corner or trackpad gesture in the settings to invoke the AgentPanel switcher.
- [ ] Homebrew packaging for app + CLI: Provide optional Homebrew distribution (cask/formula or unified strategy) on top of GitHub tagged release assets. A documented Homebrew install/upgrade path exists and is validated against release artifacts. Deferred intentionally while release work focuses on signed + notarized arm64 GitHub tagged releases.

### Exit criteria
- Missing-config onboarding path allows users to add and open a project from Switcher with explicit error surfacing and no silent defaults.
- Dedicated-space behavior is deterministic and matches the selected configuration strategy.
- Chrome profile selection allows per-project Chrome profile configuration.
- Chrome windows in project workspaces are auto-associated when title matching fails.
- Homebrew install/upgrade path is documented and validated.
- Phase 10 is split into one or more concrete follow-on phases with scoped goals; any remaining work is tracked in BACKLOG.md.
