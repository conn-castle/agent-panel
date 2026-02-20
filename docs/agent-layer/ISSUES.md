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

- Issue 2026-02-19 layout-not-restored-on-project-switch: Layout not reliably restored when returning to open project
    Priority: High. Area: Window management
    Description: When switching away and back to a project that is already open, window/panel layout often fails to return to the previously saved placement.
    Next step: Reproduce project-switch flow while logging layout save/restore events to identify where persisted state is skipped or overwritten.
    Notes: Distinct from first-open defaults issue; this occurs on return-to-open-project behavior.

- Issue 2026-02-17 new-project-layout-defaults: First open ignores default window placement
    Priority: High. Area: Window management
    Description: Opening a project for the first time (no prior saved state) does not place windows according to the configured layout defaults; window positions and sizes are incorrect.
    Next step: Reproduce with a brand-new project path and trace the first-open layout initialization path to ensure defaults are applied when no persisted layout exists.
    Notes: Likely limited to first-open state hydration; confirm behavior differs after a project has been opened once. This seems to be a persistent issue for remote SSH projects.

- Issue 2026-02-14 app-test-gap: No test target for AgentPanelApp (app-layer integration)
    Priority: Low. Area: Testing
    Description: `project.yml` only has test targets for `AgentPanelCore` and `AgentPanelCLICore`. The app delegate (auto-start at login, auto-doctor, menu wiring, focus capture) is not regression-protected by automated tests. Business logic is tested in Core, but app-layer integration (SMAppService calls, menu state, error-context auto-show) is manual-only.
    Next step: Evaluate whether an `AgentPanelAppTests` target is feasible (AppKit requires a running app host). If not, document critical app-layer paths as manual test checklist.
