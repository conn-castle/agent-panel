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

- Issue 2026-02-04 apcore-config: ApCore stores config but never uses it
    Priority: Medium. Area: Architecture
    Description: `ApCore.init(config:)` requires a `Config` parameter and stores it, but none of the methods use it. All operations are config-agnostic AeroSpace/window operations.
    Next step: Phase 2 should either use config for project-aware operations or reconsider whether ApCore should require config.
    Notes: Related to Phase 2 separation of concerns and project lifecycle work.

- Issue 2026-02-04 coreapi: App/CLI depend on internal Core APIs
    Priority: Medium. Area: Architecture
    Description: AgentPanelApp uses `ConfigLoader`, `StateStore`, `FocusHistoryStore`, and `ApCore`, which are internal or CLI-only per `docs/CORE_API.md`. This contradicts the documented API boundary.
    Next step: Either define public Core facades for these capabilities, or update CORE_API.md to explicitly allow these dependencies.
    Notes: Align with Phase 2 separation-of-concerns tasks.

- Issue 2026-02-03 doctorsev: Doctor VS Code/Chrome checks should FAIL when a project needs them
    Priority: Medium. Area: Doctor
    Description: VS Code and Chrome checks are currently WARN. They should be FAIL if any configured project would use them (same logic as the agent-layer CLI check).
    Next step: Add project config fields to specify IDE/browser requirements, then check those fields in Doctor and fail if the required app is missing.
    Notes: Blocked until project config schema includes IDE/browser requirements.
