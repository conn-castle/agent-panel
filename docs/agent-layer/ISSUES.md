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

- Issue 2026-01-31 f2a9c1: ChromeLauncher split API duplicates ensureWindow logic
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: checkExistingWindow/launchChrome/detectLaunchedWindow duplicates URL resolution, detection pipeline, and fallback logic from ensureWindow.
    Next Step: Extract shared helpers and decide on a single canonical API; remove or wrap ensureWindow.
    Notes: DRY violation raises risk of behavior drift.

- Issue 2026-01-31 e3b7d0: SwitcherPanelController hard-wires panel creation
    Priority: Medium. Area: ProjectWorkspacesApp
    Description: SwitcherPanelController constructs NSWindow-backed SwitcherPanel in init, making headless tests and dependency injection difficult.
    Next Step: Introduce a panel factory or allow injecting a panel instance for tests.

- Issue 2026-01-31 d9c4a2: Magic delay in app switcher entrypoint
    Priority: Low. Area: ProjectWorkspacesApp
    Description: ProjectWorkspacesApp.openSwitcher uses a fixed 0.05s delay before showing the switcher, which is brittle under load.
    Next Step: Replace with an event-based trigger or a named constant with documented rationale.

- Issue 2026-01-31 c6b1f8: Blocking sleep in ChromeLauncher refocus
    Priority: Low. Area: ProjectWorkspacesCore
    Description: ChromeLauncher.refocusIdeWindow sleeps synchronously, which can block the calling thread and risks UI jank if invoked on main.
    Next Step: Convert to non-blocking scheduling or document that this must run off the main thread.

- Issue 2026-01-31 b8d3e1: InMemoryStateStore lacks failure injection
    Priority: Low. Area: ProjectWorkspacesCoreTests
    Description: InMemoryStateStore only supports the happy path, limiting tests for error and recovery scenarios.
    Next Step: Add configurable failure injection and optional call tracking for assertions.

- Issue 2026-01-31 a5f2c7: ChromeLauncher ensureWindow likely unused
    Priority: Low. Area: ProjectWorkspacesCore
    Description: ActivationService uses the split Chrome API; ensureWindow is unused and may be dead code.
    Next Step: Confirm call sites; remove ensureWindow or keep only as a wrapper around the canonical path.

- Issue 2026-01-30 4e5f6g: Verbose and brittle ConfigParser
    Priority: Low. Area: ProjectWorkspacesCore
    Description: ConfigParser.swift is over 700 lines of manual, procedural parsing logic. Adding new config fields requires repetitive boilerplate, increasing the risk of inconsistent validation or defaults.
    Next Step: Consider a more declarative parsing strategy or a helper builder pattern to reduce boilerplate, while keeping the dependency constraint (TOMLDecoder only).
    Notes: High maintenance cost for config changes.

- Issue 2026-01-30 9c3d4e: Global window scan in Chrome launcher fallback
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: ChromeLauncher.attemptAllWorkspacesFallback executes a heavy `list-windows --all` scan. While correct for recovery, it risks performance issues if triggered frequently.
    Next Step: Add specific telemetry to track how often this fallback triggers; consider strict gating or fail-fast if it becomes a hotspot.
    Notes: Violates the general "scan local workspace only" preference.

- Issue 2026-01-30 0e5f6a: Mutable state accumulation in ActivationContext
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: ActivationContext aggregates significant mutable state (window IDs, logs, outcome) across a long procedural chain, making the logic hard to test and reason about.
    Next Step: Refactor into a functional pipeline with immutable intermediate results or a formal state machine/reducer.
    Notes: Technical debt that increases risk for future activation logic changes.

- Issue 2026-01-30 1a7b8c: Risky force casts in AccessibilityWindowManager
    Priority: Low. Area: ProjectWorkspacesCore
    Description: Force casts (`as! AXUIElement`, `as! AXValue`) are used in AccessibilityWindowManager (lines 100, 272, 286), posing a crash risk if Accessibility APIs return unexpected types.
    Next Step: Replace force casts with `guard let ... as?` and return structured errors or safe defaults.
    Notes: Reliability hardening.

- Issue 2026-01-30 2b9c0d: Manual JSON encoding boilerplate in ActivationService
    Priority: Low. Area: ProjectWorkspacesCore
    Description: ActivationService repeats JSON encoding and string conversion boilerplate for structured logging (`logActivation`, `logFocus`).
    Next Step: Extract a helper `logJson<T: Encodable>(...)` to ProjectWorkspacesLogger or an extension to dry up the code.
    Notes: Code hygiene.

- Issue 2026-01-28 b7v1s3: Brittle switcher visibility check
    Priority: Low. Area: ProjectWorkspacesApp
    Description: SwitcherPanelController.scheduleVisibilityCheck uses a hardcoded 0.15s delay to verify panel visibility, which is brittle on loaded systems and may cause false positive logs.
    Next Step: Replace the fixed delay with event-based observation (e.g., NSWindow.didBecomeKeyNotification) or document the limitation.
    Notes: Currently affects diagnostics only, not user functionality.

- Issue 2026-01-30 745e6a6: Inconsistent cancellation check patterns
    Priority: Low. Area: ProjectWorkspacesCore
    Description: Cancellation is checked inconsistently: context.isCancelled (computed property), cancellationToken?.isCancelled == true (direct token access), and inline checks in poll closures. This creates maintenance burden and potential for inconsistent behavior.
    Next Step: Standardize on a single pattern (prefer context.isCancelled style). For ChromeLauncher, consider passing a () -> Bool cancellation check closure.
    Notes: Does not affect correctness; code hygiene.

- Issue 2026-01-30 a1b2c3: ActivationService still centralizes too much
    Priority: High. Area: ProjectWorkspacesCore
    Description: ActivationService.swift remains over 1100 lines and still owns config loading, launches, window detection, layout, focus, and logging; step-based orchestration exists but steps are inline closures.
    Next Step: Extract step types/services into separate files and slim ActivationService to orchestration only (target sub-300 lines).
    Notes: Still the root of the mutable-context issue (0e5f6a) and constructor coupling (a1b2c9).

- Issue 2026-01-30 a1b2c6: SwitcherPanelController implicit state machine
    Priority: Medium. Area: ProjectWorkspacesApp
    Description: SwitcherPanelController has 16 mutable state variables (allProjects, filteredProjects, catalogErrorMessage, switcherSessionId, sessionOrigin, lastFilterQuery, lastStatusMessage, lastStatusLevel, expectsVisible, pendingVisibilityCheckToken, isActivating, state, activeProject, activationRequestId, activationCancellationToken, previousFocusSnapshot) with complex interdependencies. State transitions are implicit across method calls.
    Next Step: Consolidate into explicit state machine with 1-2 state enums. Consider a reducer pattern where all state changes flow through a single update function.
    Notes: High complexity; increases risk of bugs when modifying switcher behavior.

- Issue 2026-01-30 a1b2c8: Public API exposes internal error types
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: ActivationError (ActivationModels.swift lines 124-137) wraps 7+ nested error types as public associated values: AeroSpaceCommandError, AeroSpaceBinaryResolutionError, IdeLaunchError, ChromeLaunchError, LogWriteError. This leaks internal implementation details and makes the public API unstable.
    Next Step: Simplify public error cases to high-level categories (configFailed, projectNotFound, launchFailed, internalError) with detail strings. Keep internal error types internal and convert at the boundary.
    Notes: API stability concern. Changes to any nested error type currently break the public API.

- Issue 2026-01-30 a1b2c9: ActivationService constructor tight coupling
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: ActivationService public initializer (lines 34-96) accepts 12 parameters and internally constructs concrete implementations (IdeLauncher, StateStore, LayoutEngine, LayoutObserver, AccessibilityWindowManager, LayoutCoordinator) with hardcoded types. The internal test initializer (lines 99-133) requires 14 explicit parameters.
    Next Step: Accept pre-built dependencies via protocols instead of constructing them inline. Consider a builder or factory pattern to reduce parameter count. Group related parameters (poll timeouts) into a configuration struct.
    Notes: Makes testing difficult and violates dependency injection principle. Related to a1b2c3 (monolithic service).
