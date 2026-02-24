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

- Issue 2026-02-23 offscreen-window-auto-recovery-threshold: Auto-recover project windows that are materially offscreen
    Priority: Medium. Area: Window recovery
    Description: Project windows can remain partially offscreen; when more than 10% of a window is outside visible display bounds, placement should be auto-recovered.
    Next step: Add a canonical offscreen-coverage calculation and trigger project window recovery when offscreen area exceeds the 10% threshold, with regression tests across single- and multi-display layouts.

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
    Priority: Medium. Area: Window positioning
    Description: Recent runs show `project_manager.position.ide_frame_read_failed` after 10 retries with `No window found with token 'AP:<project>'`, followed by `switcher.project.layout_warning`; activation continues but layout is skipped.
    Next step: Capture AX window titles/IDs on retry exhaustion and implement a guarded fallback for IDE frame selection when token matching fails after retries.

- Issue 2026-02-21 ci-preflight-brittle: Release preflight checks rely on literal workflow text patterns
    Priority: Low. Area: CI
    Description: `scripts/ci_preflight.sh` validates key release workflow policy (runner label and Xcode floor) with exact string matching and grep patterns. Equivalent semantic workflow refactors can fail preflight even when behavior is correct.
    Next step: Refactor preflight checks to parse and validate normalized policy values (runner + Xcode minimum) rather than exact text fragments.
