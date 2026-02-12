# Backlog

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
Unscheduled user-visible features and tasks (distinct from issues; not refactors). Maintainability refactors belong in ISSUES.md.

## Format
- Insert new entries immediately below `<!-- ENTRIES START -->` (most recent first).
- Keep each entry **3–5 lines**.
- Line 1 starts with `- Backlog YYYY-MM-DD <id>:` and a short title.
- Lines 2–5 are indented by **4 spaces** and use `Key: Value`.
- Keep **exactly one blank line** between entries.
- Prevent duplicates: search the file and merge/rewrite instead of adding near-duplicates.
- When scheduled into ROADMAP.md, move the work into ROADMAP.md and remove it from this file.
- When implemented, remove the entry from this file.

### Entry template
```text
- Backlog YYYY-MM-DD abcdef: Short title
    Priority: Critical | High | Medium | Low. Area: <area>
    Description: <what the user should be able to do>
    Acceptance criteria: <clear condition to consider it done>
    Notes: <optional dependencies/constraints>
```

## Features and tasks (not scheduled)

<!-- ENTRIES START -->

- Backlog 2026-02-11 offscreen-window-rescue: Rescue off-screen floating IDE/app windows
    Priority: Medium. Area: Activation/Focus
    Description: When AgentPanel activates a project or restores focus (ap return / close / exit), detect if the target VS Code or Chrome window is mostly off-screen (stale coordinates after monitor/Space changes) and reposition it into a visible NSScreen.visibleFrame. Use macOS Accessibility (AX) APIs for absolute window positioning, map AeroSpace window-id to AX window, and add a Doctor check for the required Accessibility permission.
    Acceptance criteria: Off-screen windows are automatically repositioned on activation/return/close; Doctor checks for Accessibility permission; geometry logic and integration paths have unit tests; README documents behavior and permission requirement.
    Notes: AeroSpace floating mode does not conflict with AX positioning. No absolute positioning command exists in AeroSpace CLI — AX is the only option.

- Backlog 2026-02-09 trackpad-hotcorners: Hot Corners and Trackpad activation/switching
    Priority: Medium. Area: App/UX
    Description: Add support for Hot Corners and trackpad gestures (e.g., specific swipes) to trigger the project switcher or quickly toggle between recent projects. This aims to streamline navigation for laptop users who may prefer gesture-based interaction over keyboard shortcuts.
    Acceptance criteria: User can configure a specific screen corner or trackpad gesture in the settings to invoke the AgentPanel switcher.
