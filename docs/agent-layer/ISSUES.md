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

- Issue 2026-03-03 switcher-search-query-reset-on-launch: Switcher search text persists across launches
    Priority: Medium. Area: Switcher state lifecycle
    Description: The switcher currently reopens with the previous search text still populated on subsequent launches. Expected behavior is to start with an empty search field each launch.
    Next step: Clear search query state when the switcher is dismissed or relaunched, and add a regression test that verifies a fresh empty query on the next launch.

- Issue 2026-02-22 appdelegate-hotspot: App delegate file concentrates too many responsibilities
    Priority: Medium. Area: App architecture
    Description: `AgentPanelApp.swift` (~1.3k LOC, highest recent churn) owns lifecycle, menu composition, health orchestration, recovery actions, and menu delegate behavior in one hotspot.
    Next step: Extract focused coordinators (for example health refresh, recovery actions, and menu state) and keep AppDelegate as a composition/wiring layer.

- Issue 2026-02-22 switcher-controller-hotspot: SwitcherPanelController is an oversized high-churn hotspot
    Priority: Medium. Area: Switcher architecture
    Description: `SwitcherPanelController.swift` concentrates lifecycle, workspace retry, filtering/model updates, operation dispatch, and status presentation in ~2k LOC, increasing coupling and regression risk.
    Next step: Extract cohesive units (for example workspace retry coordination and switcher operations orchestration) while keeping the panel controller presentation-focused.
