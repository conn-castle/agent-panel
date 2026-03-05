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

- Issue 2026-03-04 zero-window-fast-fail-latency: Zero-window confirmation now waits nearly full token retry budget
    Priority: Medium. Area: window-positioning
    Description: To avoid cutting off a potentially successful final token retry, fast-fail confidence now requires full retry-attempt confidence. Persistent zero-window cases therefore still pay almost the full retry window before returning.
    Next step: Add a deterministic, monotonic confidence model (for example probe-count + monotonic elapsed with injectable clock) so permanent zero-window cases can fail early without risking late token-recovery regressions.

- Issue 2026-03-04 zero-window-probe-string-match: IDE zero-window fast-fail still relies on message text matching
    Priority: Low. Area: core
    Description: Breaker-open errors now carry structured `ApCoreError.reason` in core transport paths, but IDE zero-window probe detection still depends on regex/string parsing of `ApCoreError.message` (and some app-level paths still flatten errors to message text). Rewording text can silently alter retry/fast-fail behavior.
    Next step: Add a structured error reason (or dedicated error type) for zero-window probe failures and branch on that signal instead of message matching.

- Issue 2026-03-04 executable-resolver-timeout-validation: ExecutableResolver accepts invalid login-shell timeout values
    Priority: Low. Area: core
    Description: `ExecutableResolver(loginShellTimeoutSeconds:)` does not validate non-positive or non-finite values, allowing immediate timeouts and silent `nil` resolution behavior that obscures misconfiguration.
    Next step: Add init precondition validation (`isFinite && > 0`) and tests that document/guard the contract.

- Issue 2026-03-04 async-window-positioning: Core window positioning APIs use synchronous Thread.sleep
    Priority: Low. Area: window-positioning
    Description: `captureWindowPositions(projectId:)` and `positionWindows(projectId:)` use `Thread.sleep` inside retry loops. Callers in the app layer now dispatch these to background queues (as of `0705b99`), so UI jank is mitigated, but the Core APIs remain synchronous. Converting to `async` with `Task.sleep` would be more scalable and idiomatic Swift concurrency, but requires a broad signature refactor across Core, CLI, and tests.
    Next step: Convert `captureWindowPositions` and `positionWindows` (and their callers) to `async`, replacing `Thread.sleep` with `Task.sleep`. Scope the change to a dedicated PR.
