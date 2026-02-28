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

- Issue 2026-02-27 chrome-token-miss-no-retry: Chrome window positioning has no retry for token matching
    Priority: Medium. Area: Window positioning
    Description: Unlike IDE positioning which retries token lookup up to 10x at ~100ms intervals, Chrome positioning calls `setWindowFrames` once and skips entirely on failure. Logs show repeated `position.chrome_set_failed` ("No window found with token 'AP:\<projectId\>' for com.google.Chrome") and `recover_layout.chrome_failed` with no retry or fallback. Chrome title updates can lag just like VS Code.
    Next step: Add bounded retry logic to Chrome frame read in `positionWindows()` (analogous to IDE retry) and in `WindowRecoveryManager.recoverLayout()`, with fallback to the focused/only Chrome window when token matching fails.

- Issue 2026-02-27 switcher-selection-blocked-on-focus-capture-failure: Project selection hard-fails when pre-focus capture misses
    Priority: High. Area: Switcher activation
    Description: In 0.1.11, `project_manager.focus.capture.failed` (`aerospace list-windows --focused` exit 1) leads to `switcher.focus.not_provided`; selecting a project then stops with `Could not capture focus` instead of activating.
    Next step: Make `selectProject` tolerant of missing pre-captured focus (best-effort restore only) and add regression coverage for hotkey/menu flows with focus-capture failure.

- Issue 2026-02-27 multidisplay-ax-coordinate-conversion: AX->NSScreen conversion can produce off-display points
    Priority: High. Area: Window positioning
    Description: `AXWindowPositionerFrameIO` converts coordinates using only primary-screen height; on multi-display setups logs show points like `(2591, -510)` and `screen_frame_not_found`, causing layout to be skipped.
    Next step: Convert frame coordinates against the window's containing display/global space (not primary-only) and add automated tests for negative-Y and vertically stacked monitors.

- Issue 2026-02-27 close-workspace-stale-close-list: closeWorkspace aborts on transient single-window close misses
    Priority: Medium. Area: Workspace close reliability
    Description: `closeWorkspace` snapshots window IDs once and fails immediately if any `close --window-id` call fails; 0.1.11 logs show `Failed to close 1 windows in workspace ...` bubbling to `switcher.close_project.failed`.
    Next step: Re-query workspace windows after first-pass failures, retry unresolved IDs with bounded backoff, and include failing window IDs in `project_manager.close.failed` context.

- Issue 2026-02-27 partial-layout-capture-degrades-restore: IDE-only layout saves create degraded restore state
    Priority: Medium. Area: Layout persistence
    Description: 0.1.11 logs include `capture_position.chrome_read_failed` followed by `capture_position.saved` with `partial:true`; later `position.using_saved_ide_computed_chrome` applies mixed saved/computed layout.
    Next step: Add bounded Chrome-frame re-read before save and mark partial captures as degraded state that is not reused as canonical layout until a complete capture succeeds.

- Issue 2026-02-23 offscreen-window-auto-recovery-threshold: Refine offscreen detection to percentage-based threshold
    Priority: Low. Area: Window recovery
    Description: Auto-recovery now triggers on focus when a window's midpoint is off-screen. A more granular approach using a 10% off-screen area threshold could catch partially-offscreen windows where the midpoint is still on-screen but significant content is clipped.
    Next step: Add a canonical offscreen-coverage calculation (percentage of window area outside visible bounds) and consider triggering recovery when offscreen area exceeds 10%, with regression tests across single- and multi-display layouts.

- Issue 2026-02-23 switcher-dismiss-latency-focus-safety: Switcher dismissal feels delayed after project selection
    Priority: Medium. Area: Switcher UX & focus orchestration
    Description: After selecting a project, the switcher often remains visible longer than expected, making transition feel sluggish.
    Next step: Trace dismissal timing against focus handoff and add regression tests that preserve correct focus behavior for both project-window and non-project-window activation paths.

- Issue 2026-02-23 accessibility-permission-focus-steal: Doctor UI steals focus during accessibility permission prompt
    Priority: High. Area: Onboarding & permissions
    Description: During accessibility permission request flow, the macOS system dialog appears and Doctor re-activates almost immediately, covering the prompt and interrupting grant flow.
    Next step: Reproduce with an automated UI/integration test and gate Doctor auto-focus while any system permission prompt is active.

- Issue 2026-02-22 ap-aerospace-hotspot: ApAeroSpace mixes transport, policy, parsing, and lifecycle concerns
    Priority: Medium. Area: AeroSpace integration
    Description: `ApAeroSpace.swift` (~1k LOC, high churn) combines app lifecycle, command execution, circuit-breaker/recovery policy, parsing, and compatibility heuristics in one infrastructure hotspot.
    Next step: Decompose ApAeroSpace into focused units (command transport/retry policy, parsing, high-level operations) while preserving current behavior.

- Issue 2026-02-22 appdelegate-hotspot: App delegate file concentrates too many responsibilities
    Priority: Medium. Area: App architecture
    Description: `AgentPanelApp.swift` (~1.3k LOC, highest recent churn) owns lifecycle, menu composition, health orchestration, recovery actions, and menu delegate behavior in one hotspot.
    Next step: Extract focused coordinators (for example health refresh, recovery actions, and menu state) and keep AppDelegate as a composition/wiring layer.

- Issue 2026-02-22 switcher-controller-hotspot: SwitcherPanelController is an oversized high-churn hotspot
    Priority: Medium. Area: Switcher architecture
    Description: `SwitcherPanelController.swift` concentrates lifecycle, workspace retry, filtering/model updates, operation dispatch, and status presentation in ~2k LOC, increasing coupling and regression risk.
    Next step: Extract cohesive units (for example workspace retry coordination and switcher operations orchestration) while keeping the panel controller presentation-focused.

- Issue 2026-02-22 layout-token-miss: IDE token lookup intermittently fails and skips window positioning
    Priority: High. Area: Window positioning
    Description: Since 0.1.11 there are repeated VS Code lookup misses (`position.ide_frame_read_failed` after 10 retries and `capture_position.ide_read_failed` including `No running application with bundle ID 'com.microsoft.VSCode'`), resulting in frequent `switcher.project.layout_warning` and skipped positioning.
    Next step: On retry exhaustion, log AX inventory (PID/window ID/title) and implement guarded fallback to the focused/only VS Code window when token matching is unavailable while keeping ambiguous cases as hard failures.

- Issue 2026-02-21 ci-preflight-brittle: Release preflight checks rely on literal workflow text patterns
    Priority: Low. Area: CI
    Description: `scripts/ci_preflight.sh` validates key release workflow policy (runner label and Xcode floor) with exact string matching and grep patterns. Equivalent semantic workflow refactors can fail preflight even when behavior is correct.
    Next step: Refactor preflight checks to parse and validate normalized policy values (runner + Xcode minimum) rather than exact text fragments.
