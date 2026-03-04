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

- Issue 2026-03-03 coordinator-coverage-gap: AppHealthCoordinator and MenuWorkspaceStateCoordinator lack direct unit tests
    Priority: Low. Area: tests
    Description: These coordinators were extracted from AgentPanelApp but have no dedicated test files. Behavior regressions in refresh scheduling, focus snapshot lifecycle, or state transitions are only caught indirectly through integration-level SwitcherFocusFlowTests.
    Next step: Add unit tests for AppHealthCoordinator refresh gating and MenuWorkspaceStateCoordinator capture/clear lifecycle.

- Issue 2026-03-03 slow-syscmdrunner-tests: SystemCommandRunnerTests takes ~6.6s due to real shell spawning
    Priority: Low. Area: tests
    Description: `SystemCommandRunnerTests.swift` uses real `Process` spawning and `Thread.sleep` for circuit breaker timing tests. This accounts for ~6.6s of test time but cannot be fixed without introducing a clock abstraction into production `ApSystemCommandRunner` code.
    Next step: Add an injectable `Clock` protocol to `ApSystemCommandRunner` so circuit breaker timing tests can use a fake clock instead of real sleeps.
- Issue 2026-03-03 focus-capture-race: Switcher focus capture can be clobbered by menu refresh timing
    Priority: Medium. Area: switcher
    Description: `MenuWorkspaceStateCoordinator` background refresh can set `capturedFocus` to nil nondeterministically before panel show, because the refresh callback and focus capture happen on overlapping async paths.
    Next step: Serialize focus capture and menu refresh onto a single queue, or snapshot focus before starting background refresh.

- Issue 2026-03-03 health-coord-thread: Off-main access of main-thread-confined AppHealthCoordinator state
    Priority: Medium. Area: app-delegate
    Description: `lastHealthRefreshAt` in `AppHealthCoordinator` is read from background dispatch contexts but is documented as main-thread-only. The `requireMainThread()` guard was added but callers may still race.
    Next step: Audit all call sites of `refreshHealth()` and `lastHealthRefreshAt` to ensure main-thread dispatch.

- Issue 2026-03-03 aerospace-timing-validation: ApAeroSpace retry timing inputs are not validated
    Priority: Medium. Area: aerospace
    Description: Injectable `startupTimeoutSeconds` and `readinessCheckInterval` are not validated; zero or negative intervals can cause hot-loop polling or break timeout semantics.
    Next step: Add precondition guards (timeout > 0, interval > 0, interval < timeout) to the ApAeroSpace init.

- Issue 2026-03-03 retry-generation-race: SwitcherWorkspaceRetryCoordinator retryGeneration lacks synchronization
    Priority: Low. Area: switcher
    Description: `retryGeneration` is read/written across timer queue and main queue without synchronization. Cancel/tick interleaving could read a stale generation value.
    Next step: Protect `retryGeneration` with a lock or move all reads/writes to the same queue.

- Issue 2026-03-03 coordinator-test-flake: Several SwitcherCoordinatorTests are timing-coupled or have inverted expectations
    Priority: Low. Area: tests
    Description: Two retry tests use inverted expectations that can false-pass (never explicitly fulfilled by success). One test uses a 0.15s timeout vs 50ms timer that can flake under CI jitter. One test asserts state that may still be on main-actor cleanup path.
    Next step: Replace inverted expectations with explicit fulfillment; increase timing margins or use deterministic scheduling.
