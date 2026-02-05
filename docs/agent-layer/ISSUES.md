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

- Issue 2026-02-04 state-health: SessionManager.stateHealthIssue never surfaced in App
    Priority: Medium. Area: App/UX
    Description: `SessionManager.stateHealthIssue` is documented as requiring a user warning when non-nil, but the App never checks it. State saves can be blocked silently with only log output.
    Next step: Add UI handling in App to check `stateHealthIssue` after SessionManager init and display appropriate warning/recovery prompt.
    Notes: Documented in CORE_API.md Session Management section.

- Issue 2026-02-04 config-warn: Config warnings not surfaced to UI
    Priority: Medium. Area: Config/UX
    Description: `Config.loadDefault()` returns `Result<Config, ConfigLoadError>` which cannot convey warnings. If config is valid but has warnings (e.g., deprecated fields), they are silently dropped.
    Next step: Either change return type to include warnings, or add a separate `Config.loadDefaultWithWarnings()` method that returns warnings alongside the config.
    Notes: SwitcherPanelController clears status on success, so even if warnings were returned they'd need explicit handling.

- Issue 2026-02-04 apcore-config: ApCore stores config but never uses it
    Priority: Medium. Area: Architecture
    Description: `ApCore.init(config:)` requires a `Config` parameter and stores it, but none of the methods use it. All operations are config-agnostic AeroSpace/window operations.
    Next step: Phase 2 should either use config for project-aware operations or reconsider whether ApCore should require config.
    Notes: Related to Phase 2 separation of concerns and project lifecycle work.

- Issue 2026-02-03 doctorsev: Doctor VS Code/Chrome checks should FAIL when a project needs them
    Priority: Medium. Area: Doctor
    Description: VS Code and Chrome checks are currently WARN. They should be FAIL if any configured project would use them (same logic as the agent-layer CLI check).
    Next step: Add project config fields to specify IDE/browser requirements, then check those fields in Doctor and fail if the required app is missing.
    Notes: Blocked until project config schema includes IDE/browser requirements.
