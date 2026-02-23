# Issues

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
Deferred defects, maintainability refactors, technical debt, risks, and engineering concerns. Add an entry only when you are not fixing it now.

## Format
- Insert new entries immediately below `<!-- ENTRIES START -->` (most recent first).
- Keep each entry **3–5 lines**.
- Line 1 starts with `- Issue YYYY-MM-DD <id>:` and a short title.
- Lines 2–5 are indented by **4 spaces** and use `Key: Value`.
- Keep **exactly one blank line** between entries.
- Prevent duplicates: search the file and merge/rewrite instead of adding near-duplicates.
- When fixed, remove the entry from this file.

### Entry template
```text
- Issue YYYY-MM-DD abcdef: Short title
    Priority: Critical | High | Medium | Low. Area: <area>
    Description: <observed problem or risk>
    Next step: <smallest concrete next action>
    Notes: <optional dependencies/constraints>
```

## Open issues

<!-- ENTRIES START -->

- Issue 2026-02-23 switcher-dismiss-latency-focus-safety: Switcher dismissal feels delayed after project selection
    Priority: Medium. Area: Switcher UX & focus orchestration
    Description: After selecting a project, the switcher often remains visible longer than expected, making transition feel sluggish.
    Next step: Trace dismissal timing against focus handoff and add regression tests that preserve correct focus behavior for both project-window and non-project-window activation paths.

- Issue 2026-02-23 accessibility-permission-focus-steal: Doctor UI steals focus during accessibility permission prompt
    Priority: High. Area: Onboarding & permissions
    Description: During accessibility permission request flow, the macOS system dialog appears and Doctor re-activates almost immediately, covering the prompt and interrupting grant flow.
    Next step: Reproduce with an automated UI/integration test and gate Doctor auto-focus while any system permission prompt is active.

- Issue 2026-02-22 workspace-prefix-duplication: Workspace prefix is duplicated across modules
    Priority: Medium. Area: Core conventions
    Description: `ProjectManager` and `WindowRecoveryManager` both define the `\"ap-\"` workspace prefix locally, creating two sources of truth for project-workspace detection.
    Next step: Centralize workspace prefix ownership in one canonical Core constant and update all consumers to reference it.

- Issue 2026-02-22 ap-aerospace-hotspot: ApAeroSpace mixes transport, policy, parsing, and lifecycle concerns
    Priority: Medium. Area: AeroSpace integration
    Description: `ApAeroSpace.swift` (~1k LOC, high churn) combines app lifecycle, command execution, circuit-breaker/recovery policy, parsing, and compatibility heuristics in one infrastructure hotspot.
    Next step: Decompose ApAeroSpace into focused units (command transport/retry policy, parsing, high-level operations) while preserving current behavior.

- Issue 2026-02-22 non-project-workspace-default: Move/recovery flows hardcode non-project workspace "1"
    Priority: Medium. Area: Workspace orchestration
    Description: `moveWindowFromProject` and `recoverAllWindows` always target workspace `"1"` while other non-project flows dynamically discover candidates, creating inconsistent "back to no project" behavior.
    Next step: Define one canonical non-project destination strategy and apply it across move/recovery/restore flows, with explicit docs if workspace `"1"` remains intentional.

- Issue 2026-02-22 appdelegate-hotspot: App delegate file concentrates too many responsibilities
    Priority: Medium. Area: App architecture
    Description: `AgentPanelApp.swift` (~1.3k LOC, highest recent churn) owns lifecycle, menu composition, health orchestration, recovery actions, and menu delegate behavior in one hotspot.
    Next step: Extract focused coordinators (for example health refresh, recovery actions, and menu state) and keep AppDelegate as a composition/wiring layer.

- Issue 2026-02-22 projectmanager-thread-safety: ProjectManager is invoked from background queues despite non-thread-safe contract
    Priority: High. Area: Concurrency
    Description: `ProjectManager` documents main-thread-only usage, but `captureCurrentFocus`, `closeProject`, and `exitToNonProjectWindow` are called from global queues in app/switcher paths, risking races in mutable focus/config state.
    Next step: Enforce a single concurrency boundary for ProjectManager (MainActor or serial executor) and route mutating operations through that boundary.
    Notes: Likely contributor to `non-project-space-return-flaky` behavior.

- Issue 2026-02-22 launch-at-login-rollback: Launch-at-login rollback failures are silently ignored
    Priority: Medium. Area: Startup & config
    Description: `toggleLaunchAtLogin()` uses `try?` during rollback after config write failure, so rollback errors are swallowed and runtime `SMAppService` state can diverge from config.
    Next step: Replace silent rollback with explicit error handling/logging, then reconcile and surface mismatch between service status and config state.

- Issue 2026-02-22 switcher-controller-hotspot: SwitcherPanelController is an oversized high-churn hotspot
    Priority: Medium. Area: Switcher architecture
    Description: `SwitcherPanelController.swift` concentrates lifecycle, workspace retry, filtering/model updates, operation dispatch, and status presentation in ~2k LOC, increasing coupling and regression risk.
    Next step: Extract cohesive units (for example workspace retry coordination and switcher operations orchestration) while keeping the panel controller presentation-focused.

- Issue 2026-02-22 log-jsonl-corruption: Structured log file occasionally contains malformed non-JSON lines
    Priority: High. Area: Logging
    Description: Runtime logs produced at least one malformed fragment (`-02-22T00:07:13.863Z"}`) that is not valid JSON, which breaks JSONL parsers and weakens diagnostics.
    Next step: Serialize app log writes/rotation with a single-writer lock strategy and add a stress test that validates every emitted line decodes as `LogEntry`.

- Issue 2026-02-22 layout-token-miss: IDE token lookup intermittently fails and skips window positioning
    Priority: Medium. Area: Window positioning
    Description: Recent runs show `project_manager.position.ide_frame_read_failed` after 10 retries with `No window found with token 'AP:<project>'`, followed by `switcher.project.layout_warning`; activation continues but layout is skipped.
    Next step: Capture AX window titles/IDs on retry exhaustion and implement a guarded fallback for IDE frame selection when token matching fails after retries.

- Issue 2026-02-22 non-project-space-return-flaky: Back-to-non-project-space action frequently fails
    Priority: Medium. Area: Navigation
    Description: Returning from a project space to a non-project space is unreliable and often does not complete correctly, causing inconsistent workspace state.
    Next step: Reproduce with a deterministic test case and trace the navigation/state transition path to isolate the failure point.

- Issue 2026-02-21 ci-preflight-brittle: Release preflight checks rely on literal workflow text patterns
    Priority: Low. Area: CI
    Description: `scripts/ci_preflight.sh` validates key release workflow policy (runner label and Xcode floor) with exact string matching and grep patterns. Equivalent semantic workflow refactors can fail preflight even when behavior is correct.
    Next step: Refactor preflight checks to parse and validate normalized policy values (runner + Xcode minimum) rather than exact text fragments.

- Issue 2026-02-14 app-test-gap: No test target for AgentPanelApp (app-layer integration)
    Priority: Low. Area: Testing
    Description: `project.yml` only has test targets for `AgentPanelCore` and `AgentPanelCLICore`. The app delegate (auto-start at login, auto-doctor, menu wiring, focus capture) is not regression-protected by automated tests. Business logic is tested in Core, but app-layer integration (SMAppService calls, menu state, error-context auto-show) is manual-only.
    Next step: Evaluate whether an `AgentPanelAppTests` target is feasible (AppKit requires a running app host). If not, document critical app-layer paths as manual test checklist.
