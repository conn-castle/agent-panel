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

- Issue 2026-03-08 lockord: Lock ordering inversion between stateQueue and persistenceQueue
    Priority: High. Area: AgentPanelCore/ProjectManager
    Description: `loadFocusHistory` acquires persistenceQueue then stateQueue; `persistFocusHistory` acquires stateQueue then persistenceQueue. AB-BA lock ordering is structurally unsound. Mitigated because `loadFocusHistory` only runs during `init`.
    Next step: Establish strict lock ordering (always stateQueue before persistenceQueue); refactor `loadFocusHistory` to read from persistence first, then update state.

- Issue 2026-03-08 focblk: Unbounded blocking time in focusWindowStableSync loop
    Priority: High. Area: AgentPanelCore/ProjectManager+FocusCapture
    Description: `focusWindowStableSync` blocks for up to `windowPollTimeout` (10s) per attempt. Called from `restoreNonProjectFocusFromStack` in a loop over up to 20 stack entries, worst-case 200s blocking. No `dispatchPrecondition` enforces off-main-thread.
    Next step: Add `dispatchPrecondition(condition: .notOnQueue(.main))` and a total restore budget timeout. Consider trying only the first few candidates.

- Issue 2026-03-08 pmsafe: ProjectManager thread-safety contract is unclear
    Priority: High. Area: AgentPanelApp/AgentPanelApp.swift, AgentPanelCore/ProjectManager
    Description: ProjectManager is called from both main and background threads with contradictory comments ("not thread-safe" vs "serializes state/persistence"). Some methods have internal locking, others do not. Ad-hoc mixture is the most dangerous concurrency pattern.
    Next step: Document the formal thread-safety contract. Either make fully thread-safe with internal locking or confine to a specific actor/queue.

- Issue 2026-03-08 nonsend: Non-Sendable struct captured in async dispatch in ApAeroSpace
    Priority: High. Area: AgentPanelCore/AeroSpace/ApAeroSpace.swift:800-825
    Description: `ApAeroSpace` (a struct) is captured in `DispatchQueue.global().async` closure. Under strict Swift concurrency checking this is flagged. Reference-type dependencies propagate correctly but the pattern is unsound for Swift 6.
    Next step: Extract reference-type dependencies (transport, circuitBreaker, checker) into local bindings before the closure and capture only those.

- Issue 2026-03-08 recstk: Recovery in-progress flag has no timeout/safety mechanism
    Priority: Medium. Area: AgentPanelCore/AeroSpace/AeroSpaceCircuitBreaker.swift
    Description: `_isRecoveryInProgress` is set in `beginRecovery()` but only cleared in `endRecovery()` or `reset()`. If recovery is abandoned without calling `endRecovery`, the flag stays true permanently, blocking all future recovery.
    Next step: Add a safety timeout (e.g., auto-clear after 60s) or increment `recoveryAttemptCount` in `beginRecovery()`.

- Issue 2026-03-08 retrydup: Duplicated retry-with-fallback boilerplate in window positioning
    Priority: Medium. Area: AgentPanelCore/ProjectManager+WindowPositioningActivation.swift, +WindowPositioningCapture.swift
    Description: The retry-with-fallback pattern for transient window token errors is repeated 4 times with nearly identical structure. ~40% of code volume in positioning files, most likely source of copy-paste inconsistencies.
    Next step: Extract a generic `retryTransientWindowOp` helper that encapsulates the retry loop, sleep, and fallback logic.

- Issue 2026-03-08 docrun: Doctor.run() is a ~400-line monolith
    Priority: Medium. Area: AgentPanelCore/Doctor.swift:348-736
    Description: The `run()` method accumulates local state across sequential sections, making it difficult to test sections in isolation. Refactoring into per-section methods returning `[DoctorFinding]` would improve testability.
    Next step: Extract each section (homebrew, aerospace, config/project, app, accessibility/hotkey) into private methods.

- Issue 2026-03-08 gcdtsk: Redundant DispatchQueue.global + Task wrapping pattern
    Priority: Medium. Area: AgentPanelApp/SwitcherOperationCoordinator.swift, RecoveryOperationCoordinator.swift
    Description: Multiple methods dispatch to `DispatchQueue.global().async` then immediately create a `Task` inside. The outer GCD dispatch is redundant — `Task.detached` would suffice.
    Next step: Replace `DispatchQueue.global().async { Task { ... } }` with `Task.detached(priority:) { ... }`.

- Issue 2026-03-08 hlthrd: healthCoordinator.lastHealthRefreshAt read from background thread
    Priority: Medium. Area: AgentPanelApp/AgentPanelApp.swift:375-379
    Description: Inside `onProjectsChanged` closure (runs on background queue), `healthCoordinator?.lastHealthRefreshAt` is read. AppHealthCoordinator is documented as main-thread-confined, making this a data race.
    Next step: Move the `lastHealthRefreshAt` check inside the `DispatchQueue.main.async` block that follows.

- Issue 2026-03-08 ovldlk: WindowCycleOverlayCoordinator potential deadlock with DispatchQueue.main.sync
    Priority: Medium. Area: AgentPanelApp/WindowCycleOverlayCoordinator.swift:128
    Description: `isOverlaySuppressed()` uses `DispatchQueue.main.sync` from within a serial queue. If any code path calls start/advance/commit from the main thread, this deadlocks. Currently mitigated by `Thread.isMainThread` early-return.
    Next step: Read `shouldSuppressOverlay()` on main thread before dispatching to queue, passing result as parameter.

- Issue 2026-03-08 listwe: listAllWindows silently swallows infrastructure errors
    Priority: Medium. Area: AgentPanelCore/AeroSpace/ApAeroSpace.swift:741-761
    Description: `listAllWindows()` uses `case .failure: continue` for per-workspace queries. This swallows circuit-breaker-open and timeout errors, returning partial results without indication.
    Next step: Distinguish transient errors from infrastructure errors; propagate breaker-open/timeout immediately.

- Issue 2026-03-08 compat: Compatibility checks cascade-fail through circuit breaker
    Priority: Medium. Area: AgentPanelCore/AeroSpace/ApAeroSpace.swift:282-319
    Description: `checkCompatibility` runs 6 `--help` checks via `concurrentPerform`. If the first times out and trips the breaker, remaining 5 immediately fail with misleading messages.
    Next step: Bypass the circuit breaker for `--help` checks or catch breaker-open errors distinctly.

- Issue 2026-03-08 rdyprb: Readiness probe tests CLI only, not daemon connectivity
    Priority: Low. Area: AgentPanelCore/AeroSpace/ApAeroSpace.swift:1009-1020
    Description: `isCliReadyOffBreakerProbe()` uses `--help` which only tests CLI availability, not daemon health. A daemon-backed command like `list-workspaces --focused` would be more reliable.
    Next step: Use a daemon-backed command for the readiness probe, consistent with `recoveryProbeResultOffBreaker()`.

- Issue 2026-03-08 oprguard: SwitcherOperationCoordinator guards rely on implicit main-thread confinement
    Priority: Medium. Area: AgentPanelApp/SwitcherOperationCoordinator.swift
    Description: Operation guard flags (isActivating, isExitingToNonProject, etc.) are only safe because all reads/writes happen on main. No dispatchPrecondition enforces this.
    Next step: Add `dispatchPrecondition(condition: .onQueue(.main))` to `resetGuards()` and guard-checking methods, or mark the class as `@MainActor`.

- Issue 2026-03-08 errmsg: Duplicated projectErrorMessage helper
    Priority: Low. Area: AgentPanelApp/SwitcherOperationCoordinator.swift, SwitcherPanelController+InteractionUI.swift
    Description: `projectErrorMessage(_ error: ProjectError) -> String` is identically duplicated in two files.
    Next step: Extract into a shared extension on `ProjectError` (e.g., `var userFacingMessage: String`).

- Issue 2026-03-08 cfgwrt: ConfigWriteBack trailingCommentSegment misidentifies # inside TOML strings
    Priority: Medium. Area: AgentPanelCore/ConfigWriteBack.swift:126-135
    Description: `trailingCommentSegment` finds first `#` character, which would match `#` inside quoted hex colors. Currently latent (only used for `autoStartAtLogin` boolean lines) but would break if extended.
    Next step: Document constraint or implement TOML-aware `#` detection that skips characters inside quoted strings.

- Issue 2026-03-08 fsdef: FileSystem protocol directoryExists default returns false
    Priority: Medium. Area: AgentPanelCore/DependenciesFileSystem.swift:30-32
    Description: Protocol default for `directoryExists` returns `false` unconditionally. Test doubles that forget to implement it silently report no directories exist.
    Next step: Remove the default implementation to force conformers to implement `directoryExists`.

- Issue 2026-03-08 dmgxit: create-dmg exit code 2 not handled in ci_package.sh
    Priority: Medium. Area: scripts/ci_package.sh:47
    Description: `create-dmg` returns exit code 2 when it successfully creates the DMG but cannot set a custom icon (common in headless CI). With `set -e` this fails the script.
    Next step: Check exit code explicitly; accept 0 and 2 as success when the output file exists.

- Issue 2026-03-08 ntrzlog: ci_notarize.sh does not capture submission ID on failure
    Priority: Medium. Area: scripts/ci_notarize.sh:31-36
    Description: If notarization fails, no submission ID is captured and `notarytool log` is not called, making debugging difficult.
    Next step: Capture `notarytool submit` output, extract submission ID, and call `notarytool log` on failure.

- Issue 2026-03-08 ciarch: ci_archive.sh does not validate xcbeautify availability
    Priority: Low. Area: scripts/ci_archive.sh:42
    Description: The script pipes through `xcbeautify` without checking if it is installed, unlike `build.sh` and `build_dev.sh`.
    Next step: Add `command -v xcbeautify` check for consistency.
