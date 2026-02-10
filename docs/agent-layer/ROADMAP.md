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
- Chrome tab persistence/restore via AppleScript with snapshot-is-truth design; URLs captured verbatim on close and restored on activate.
- LIFO focus stack replacing single-slot design; "exit project space" returns to last non-project window.
- Agent Layer config: global `[agentLayer] enabled` default (false), per-project override, SSH+AL mutual exclusion at parse time.
- SSH projects: `project.remote` (ssh-remote+user@host) + remote absolute `project.path`; workspace uses `vscode-remote://...` folder URI + `remoteAuthority` key; Doctor validates via `ssh test -d`.
- Agent Layer launcher: `ApAgentLayerVSCodeLauncher` creates workspace with `AP:<id>` tag, runs `al sync` (CWD = project path) then `code --new-window <workspace>` directly. Two-step approach avoids dual-window bug in `al vscode` (unconditionally appends `.` to code args). `ProjectManager` selects launcher based on `project.useAgentLayer`.
- `CommandRunning` extended with `workingDirectory: String?` parameter; shared workspace helper `ApIdeToken.createWorkspaceFile()`.
- Config hardening: SSH authority option injection rejected at parse time (authorities starting with `-`); local paths validated as absolute; Doctor ssh includes `--` option terminator for defense-in-depth.
- PATH propagation: `ApSystemCommandRunner` builds augmented PATH (standard paths + login shell PATH + process PATH) with 5s timeout, user's `$SHELL` (validated as absolute path), deduplication, 2s pipe EOF timeout. Child processes receive this environment. Tested in `SystemCommandRunnerTests`.
- Focus restore workspace fallback: `closeProject` and `exitToNonProjectWindow` fall back to first non-project workspace when focus stack is exhausted. Switcher dismiss tries workspace-level focus before app activation.
- Switcher refreshes captured focus after `closeProject` (to the newly restored focus) so dismiss and subsequent selections don't use stale pre-switcher focus.

## Phase 6 — Extra non-required features

### Goal
- Deliver optional UX enhancements that improve convenience but are not required for daily-driver readiness.

### Tasks
- [ ] Add dropdown menu item to move the currently focused window to any of the open project's workspaces. The top level menu item would be Add Window to Project -> [Project 1, Project 2, Project 3]
- [ ] Favorites/stars for projects (persisted) and UI affordances.
- [ ] Fuzzy search with ranking in the switcher.
- [ ] Auto-start at login (opt-in).
- [ ] Automatically run Doctor on operational errors (for example project startup failure or command failure), either in the background or by surfacing a diagnostic report.
- [ ] Add a setting/command to hide the AeroSpace menu bar icon while preserving AeroSpace window-management behavior (investigate headless/hidden-icon support).
- [ ] Add Chrome visual differentiation that matches the associated VS Code project color/theme (for example via profile customization or theme injection, using VSCodeColorPalette guidance as needed). Also, need to actually set VS Code project color, since that's not done today.

### Exit criteria
- Optional UX features are implemented without regressing required daily-driver workflows.
- Operational failures trigger automatic diagnostics in a predictable, documented way.
- AeroSpace icon visibility can be configured without disabling functional behavior.
- Chrome/VS Code visual correlation is present for projects where the feature is enabled.
- Behavior and limitations are documented where needed.
- New behavior is covered by tests.

## Phase 7 — Release: packaging, verification, and documentation

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

## Phase 8 — Future post-release features

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
- Phase 8 is split into one or more concrete follow-on phases with scoped goals; any remaining work is tracked in BACKLOG.md.
