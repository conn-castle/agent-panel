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

- Issue 2026-03-04 doctor-circuit-breaker-bypass: Doctor CLI check fails when circuit breaker is open
    Priority: High. Area: doctor
    Description: `ApAeroSpace.isCliAvailable()` routes through `runAerospace()` which checks the circuit breaker first. When the breaker is open, the doctor falsely reports "aerospace CLI not available" and "Critical: AeroSpace setup incomplete" even though AeroSpace.app is installed and running. The doctor is a diagnostic tool and should independently verify actual system state, not reflect cached circuit-breaker state.
    Next step: Add a direct CLI check method that bypasses the circuit breaker (e.g., call the command runner directly with `aerospace --help`), or give the Doctor its own `ApAeroSpace` instance with the circuit breaker disabled/reset.

- Issue 2026-03-04 circuit-breaker-cascade-noise: Single AeroSpace timeout generates ~60 duplicate warnings across layers
    Priority: Medium. Area: logging
    Description: When the circuit breaker trips, each layer (ProjectManager focus capture, ProjectManager workspace state, Switcher focus, Switcher workspace state) independently logs warnings on every hotkey press and retry tick. A single timeout event at 17:56:46 generated ~60 of the 72 total warnings in today's log. No deduplication or throttling exists.
    Next step: Suppress per-call warnings when the circuit breaker is already open (the transport layer already logs `circuit_breaker.tripped` once). Alternatively, add a throttle so repeated breaker-open failures log at most once per cooldown period per event type.

- Issue 2026-03-04 token-retry-no-fast-fail: IDE window token retry loops 10 times when 0 windows are enumerated
    Priority: Medium. Area: window-positioning
    Description: In `ProjectManager+WindowPositioningActivation.swift`, the IDE frame read retries up to 10 times (at 0.1s intervals) even when `getFallbackWindowFrame()` returns "No windows found for com.microsoft.VSCode (0 windows enumerated)". Zero windows is a permanent condition (app not running or no windows open), making retries pointless. This adds ~1s latency to project switches when VS Code isn't open.
    Next step: Detect the "0 windows enumerated" condition in the fallback error and exit the retry loop immediately instead of continuing.

- Issue 2026-03-03 coordinator-coverage-gap: AppHealthCoordinator and MenuWorkspaceStateCoordinator lack direct unit tests
    Priority: Low. Area: tests
    Description: These coordinators were extracted from AgentPanelApp but have no dedicated test files. Behavior regressions in refresh scheduling, focus snapshot lifecycle, or state transitions are only caught indirectly through integration-level SwitcherFocusFlowTests.
    Next step: Add unit tests for AppHealthCoordinator refresh gating and MenuWorkspaceStateCoordinator capture/clear lifecycle.

- Issue 2026-03-03 slow-syscmdrunner-tests: SystemCommandRunner login-shell tests take ~6.6s due to real shell spawning
    Priority: Low. Area: tests
    Description: `SystemCommandRunnerLoginShellTests.swift` uses real `Process` spawning and timeout waits to validate login-shell fallback behavior. This accounts for ~6.6s of test time but cannot be fixed without introducing a clock abstraction into production `ApSystemCommandRunner` code.
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
