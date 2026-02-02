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
    Priority: Medium. Area: AgentPanelApp
    Description: SwitcherPanelController constructs NSWindow-backed SwitcherPanel in init, making headless tests and dependency injection difficult.
    Next step: Introduce a panel factory or allow injecting a panel instance for tests.

- Issue 2026-01-31 d9c4a2: Magic delay in app switcher entrypoint
    Priority: Low. Area: AgentPanelApp
    Description: AgentPanelApp.openSwitcher uses a fixed 0.05s delay before showing the switcher, which is brittle under load.
    Next step: Replace with an event-based trigger or a named constant with documented rationale.

- Issue 2026-01-30 4e5f6g: Verbose and brittle config parsing
    Priority: Low. Area: AgentPanelCore
    Description: Config.swift now contains the ~700-line manual parsing logic. Adding new config fields requires repetitive boilerplate, increasing the risk of inconsistent validation or defaults.
    Next step: Consider a more declarative parsing strategy or a helper builder pattern to reduce boilerplate, while keeping the dependency constraint (TOMLDecoder only).
    Notes: High maintenance cost for config changes.

- Issue 2026-01-28 b7v1s3: Brittle switcher visibility check
    Priority: Low. Area: AgentPanelApp
    Description: SwitcherPanelController.scheduleVisibilityCheck uses a hardcoded 0.15s delay to verify panel visibility, which is brittle on loaded systems and may cause false positive logs.
    Next step: Replace the fixed delay with event-based observation (e.g., NSWindow.didBecomeKeyNotification) or document the limitation.
    Notes: Currently affects diagnostics only, not user functionality.
