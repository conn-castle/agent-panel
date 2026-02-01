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

- Issue 2026-01-31 e3b7d0: SwitcherPanelController hard-wires panel creation
    Priority: Medium. Area: ProjectWorkspacesApp
    Description: SwitcherPanelController constructs NSWindow-backed SwitcherPanel in init, making headless tests and dependency injection difficult.
    Next Step: Introduce a panel factory or allow injecting a panel instance for tests.

- Issue 2026-01-31 d9c4a2: Magic delay in app switcher entrypoint
    Priority: Low. Area: ProjectWorkspacesApp
    Description: ProjectWorkspacesApp.openSwitcher uses a fixed 0.05s delay before showing the switcher, which is brittle under load.
    Next Step: Replace with an event-based trigger or a named constant with documented rationale.

- Issue 2026-01-30 4e5f6g: Verbose and brittle ConfigParser
    Priority: Low. Area: ProjectWorkspacesCore
    Description: ConfigParser.swift is over 700 lines of manual, procedural parsing logic. Adding new config fields requires repetitive boilerplate, increasing the risk of inconsistent validation or defaults.
    Next Step: Consider a more declarative parsing strategy or a helper builder pattern to reduce boilerplate, while keeping the dependency constraint (TOMLDecoder only).
    Notes: High maintenance cost for config changes.

- Issue 2026-01-30 0e5f6a: Mutable state accumulation in ActivationContext
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: ActivationContext aggregates significant mutable state (window IDs, logs, outcome) across a long procedural chain, making the logic hard to test and reason about.
    Next Step: Refactor into a functional pipeline with immutable intermediate results or a formal state machine/reducer.
    Notes: Technical debt that increases risk for future activation logic changes.

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
    Next Step: Standardize on a single pattern (prefer context.isCancelled style) across poll loops.
    Notes: Does not affect correctness; code hygiene.

- Issue 2026-01-30 a1b2c3: ActivationService still centralizes too much
    Priority: High. Area: ProjectWorkspacesCore
    Description: ActivationService.swift remains large and still owns config loading, AeroSpace command orchestration, window resolution, layout, focus, and logging.
    Next Step: Extract steps into dedicated types or files and slim ActivationService to orchestration only (target sub-300 lines).
    Notes: Still the root of the mutable-context issue (0e5f6a) and constructor coupling (a1b2c9).

- Issue 2026-01-30 a1b2c6: SwitcherPanelController implicit state machine
    Priority: Medium. Area: ProjectWorkspacesApp
    Description: SwitcherPanelController has 16 mutable state variables (allProjects, filteredProjects, catalogErrorMessage, switcherSessionId, sessionOrigin, lastFilterQuery, lastStatusMessage, lastStatusLevel, expectsVisible, pendingVisibilityCheckToken, isActivating, state, activeProject, activationRequestId, activationCancellationToken, previousFocusSnapshot) with complex interdependencies. State transitions are implicit across method calls.
    Next Step: Consolidate into explicit state machine with 1-2 state enums. Consider a reducer pattern where all state changes flow through a single update function.
    Notes: High complexity; increases risk of bugs when modifying switcher behavior.

- Issue 2026-01-30 a1b2c9: ActivationService constructor tight coupling
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: ActivationService public initializer still constructs concrete dependencies (ConfigLoader, IdeAppResolver, DefaultAeroSpaceBinaryResolver) and exposes a long parameter list for configuration.
    Next Step: Accept pre-built dependencies via protocols instead of constructing them inline. Consider a builder or factory pattern to reduce parameter count and group timing settings into a config struct.
    Notes: Makes testing and reuse harder; related to a1b2c3 (monolithic service).
