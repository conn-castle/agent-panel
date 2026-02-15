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

- Issue 2026-02-15 space-switching: Project selection fails to switch macOS desktop spaces
    Priority: High. Area: Window Management
    Description: When selecting a project from the menu while on a different macOS desktop space, the application sometimes fails to switch to the correct space where the project windows are located.
    Next step: Investigate how `ProjectManager` and `AeroSpace` handle space/workspace switching and ensure reliable focus transitions across macOS spaces.

- Issue 2026-02-15 recovery-layout: Window recovery should use default layout positions
    Priority: Medium. Area: Window Management
    Description: `WindowRecoveryManager` (via `AXWindowPositioner.recoverWindow`) currently centers windows on screen during recovery. It should instead attempt to move windows to their default positions based on project configs or global defaults, rather than just centering them.
    Next step: Update `WindowRecoveryManager` to accept layout configuration and apply it during recovery.

- Issue 2026-02-14 app-test-gap: No test target for AgentPanelApp (app-layer integration)
    Priority: Low. Area: Testing
    Description: `project.yml` only has test targets for `AgentPanelCore` and `AgentPanelCLICore`. The app delegate (auto-start at login, auto-doctor, menu wiring, focus capture) is not regression-protected by automated tests. Business logic is tested in Core, but app-layer integration (SMAppService calls, menu state, error-context auto-show) is manual-only.
    Next step: Evaluate whether an `AgentPanelAppTests` target is feasible (AppKit requires a running app host). If not, document critical app-layer paths as manual test checklist.

