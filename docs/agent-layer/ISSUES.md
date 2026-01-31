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

- Issue 2026-01-30 3d1e2f: Duplicate command execution logic
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: IdeLauncher and ChromeLauncher both implement private `runCommand` methods with identical error handling patterns (converting exit codes to Results).
    Next Step: Extract a shared `ProcessRunner` helper or extension on `CommandRunning` to centralize this logic.
    Notes: DRY violation.

- Issue 2026-01-30 4e5f6g: Verbose and brittle ConfigParser
    Priority: Low. Area: ProjectWorkspacesCore
    Description: ConfigParser.swift is over 700 lines of manual, procedural parsing logic. Adding new config fields requires repetitive boilerplate, increasing the risk of inconsistent validation or defaults.
    Next Step: Consider a more declarative parsing strategy or a helper builder pattern to reduce boilerplate, while keeping the dependency constraint (TOMLDecoder only).
    Notes: High maintenance cost for config changes.

- Issue 2026-01-30 8a2f1b: Inefficient AeroSpace client creation in Switcher

    Priority: High. Area: ProjectWorkspacesApp
    Description: AeroSpaceSwitcherService resolves the binary and creates a new AeroSpaceClient on every interaction (snapshot, restore, check), causing unnecessary filesystem/shell overhead and UI latency.
    Next Step: Refactor AeroSpaceSwitcherService to resolve the binary once at initialization and reuse a single AeroSpaceClient instance.
    Notes: Critical for switcher responsiveness.

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

- Issue 2026-01-30 745e6a4: Duplicated window detection pipeline configuration
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: ActivationService and ChromeLauncher both contain identical private methods for creating WindowDetectionPipeline, PollSchedule, and LaunchDetectionTimeouts (~90 lines of duplicated code across windowDetectionPipeline, launchDetectionTimeouts, fastPollIntervalMs, workspacePollSchedule, focusedFastPollSchedule, focusedSteadyPollSchedule).
    Next Step: Extract a shared WindowDetectionConfiguration factory that both services can use.
    Notes: WindowDetection.swift defines the shared types but not a shared configuration factory.

- Issue 2026-01-30 745e6a5: Unused ensureChromeWindow method in ActivationService
    Priority: Low. Area: ProjectWorkspacesCore
    Description: The ensureChromeWindow method (ActivationService.swift lines 771-823) is dead code after the parallel launch refactor introduced in Decision 2026-01-30 parallel.
    Next Step: Remove the unused method.
    Notes: Superseded by checkExistingWindow/launchChrome/detectLaunchedWindow pattern.

- Issue 2026-01-30 745e6a6: Inconsistent cancellation check patterns
    Priority: Low. Area: ProjectWorkspacesCore
    Description: Cancellation is checked inconsistently: context.isCancelled (computed property), cancellationToken?.isCancelled == true (direct token access), and inline checks in poll closures. This creates maintenance burden and potential for inconsistent behavior.
    Next Step: Standardize on a single pattern (prefer context.isCancelled style). For ChromeLauncher, consider passing a () -> Bool cancellation check closure.
    Notes: Does not affect correctness; code hygiene.

- Issue 2026-01-30 745e6a7: Magic numbers in UI timing constants
    Priority: Low. Area: ProjectWorkspacesApp
    Description: SwitcherPanelController uses hardcoded timing values (0.15s for visibility check at line 438, 0.05s for post-dismiss focus at line 713) without named constants, making the code harder to understand and tune.
    Next Step: Extract named constants (e.g., SwitcherTiming.visibilityCheckDelay, SwitcherTiming.postDismissFocusDelay).
    Notes: Related to Issue b7v1s3 but broader in scope.

- Issue 2026-01-30 a1b2c3: Monolithic ActivationService (God object)
    Priority: High. Area: ProjectWorkspacesCore
    Description: ActivationService.swift is 1185 lines with ~30 private functions handling config loading, AeroSpace resolution, IDE launching, Chrome launching, window detection, layout coordination, focus management, and logging. The main runActivation() function is 182 lines with deeply nested control flow.
    Next Step: Extract step-based orchestration pattern with separate types (LoadConfigStep, ResolveIdeStep, LaunchIdeStep, etc.) that implement a common ActivationStep protocol. Target: reduce orchestration to 20-30 lines.
    Notes: Root cause of several other issues (0e5f6a mutable state, 745e6a4 duplication). Fixing this enables other improvements.

- Issue 2026-01-30 a1b2c4: Missing StateStoring protocol
    Priority: High. Area: ProjectWorkspacesCore
    Description: StateStore is a concrete class without a protocol abstraction. Used directly in LayoutCoordinator (line 33) and ActivationService (line 80). Cannot be mocked for testing or swapped for alternative implementations (in-memory, database, cloud).
    Next Step: Extract StateStoring protocol with load() and save() methods. Update LayoutCoordinator and any other consumers to depend on the protocol.
    Notes: Testability and abstraction improvement. LayoutEngine has the same issue but is lower priority.

- Issue 2026-01-30 a1b2c5: App layer leaky abstraction with AeroSpace
    Priority: High. Area: ProjectWorkspacesApp
    Description: SwitcherPanelController.swift lines 1167-1242 define AeroSpaceSwitcherService which constructs AeroSpaceClient directly using DefaultAeroSpaceBinaryResolver and DefaultAeroSpaceCommandRunner. The App layer should not know about these low-level Core types.
    Next Step: Create a WorkspaceManagement facade protocol in Core (captureCurrentFocus, restoreFocus, workspaceExists) and provide it to App layer. Move AeroSpaceSwitcherService implementation to Core.
    Notes: Extends Issue 8a2f1b. Proper layering would also solve the repeated client creation problem.

- Issue 2026-01-30 a1b2c6: SwitcherPanelController implicit state machine
    Priority: Medium. Area: ProjectWorkspacesApp
    Description: SwitcherPanelController has 16 mutable state variables (allProjects, filteredProjects, catalogErrorMessage, switcherSessionId, sessionOrigin, lastFilterQuery, lastStatusMessage, lastStatusLevel, expectsVisible, pendingVisibilityCheckToken, isActivating, state, activeProject, activationRequestId, activationCancellationToken, previousFocusSnapshot) with complex interdependencies. State transitions are implicit across method calls.
    Next Step: Consolidate into explicit state machine with 1-2 state enums. Consider a reducer pattern where all state changes flow through a single update function.
    Notes: High complexity; increases risk of bugs when modifying switcher behavior.

- Issue 2026-01-30 a1b2c7: Duplicate error enum cases
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: ProcessCommandError (IdeLaunchModels.swift lines 31-34) and AeroSpaceCommandError (AeroSpaceErrors.swift lines 5-6) both define identical cases: launchFailed(command:underlyingError:) and nonZeroExit(command:result:). This violates DRY and means error handling logic is duplicated.
    Next Step: Extract a unified CommandExecutionError enum that both can use, or have ProcessCommandError extend/wrap AeroSpaceCommandError.
    Notes: Related to Issue 3d1e2f (duplicate runCommand logic). Fixing errors first would make the runCommand extraction cleaner.

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
