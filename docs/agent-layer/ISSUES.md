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

- Issue 2026-03-10 leaveproj: Fallback focus can strand the app in project space
    Priority: High. Area: focus restoration
    Description: When there are no recent non-project windows, the app can remain in project space instead of searching for any non-project destination. We should always leave project space, even if the only available fallback is an empty Aerospace workspace.
    Next step: Update the non-project focus restoration flow to search for any eligible non-project target when the recent-window path is empty and pick one before returning.
    Notes: Prefer a non-project window when available; otherwise focus an empty Aerospace workspace so the app still exits project space.

- Issue 2026-03-09 testgap: Missing unit tests for new extraction/refactor surfaces
    Priority: Medium. Area: tests
    Description: Several refactored or newly extracted methods lack direct unit test coverage: `retryTransientWindowOp` (retry+fallback logic), `AeroSpaceCircuitBreaker.beginRecovery` 60s stuck-recovery timeout, `listAllWindows` infrastructure error propagation (circuitBreakerOpen/timeout), `ProjectError.userFacingMessage`, `performBackgroundBreakerRecovery` readiness polling, and `restoreNonProjectFocusFromStack` multi-candidate loop.
    Next step: Add focused unit tests for `retryTransientWindowOp` covering immediate success, transient retry, fallback invocation, and permanent failure paths.
