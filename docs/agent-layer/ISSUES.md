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

- Issue 2026-03-05 async-switcher-main-thread-tests: App async wrapper threading coverage gap
    Priority: Low. Area: app-tests
    Description: The new `Task` bridges around close/exit/recovery flows in `AgentPanelApp` and `SwitcherOperationCoordinator` are covered indirectly, but there are no targeted tests asserting main-thread completion/progress delivery after the async conversion.
    Next step: Add focused App tests that verify completion callbacks and UI update closures run on the main thread for the async recovery/close paths.
