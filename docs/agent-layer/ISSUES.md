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

- Issue 2026-02-14 peacock-reverts: Peacock colors sometimes revert shortly after loading
    Priority: Medium. Area: VSCode/Peacock
    Description: Peacock extension colors are observed to load correctly but then revert back to their previous state after a few seconds. The root cause for this "undoing" of the color application is unknown.
    Next step: Investigate AgentPanel's VSCode settings synchronization and Peacock extension behavior to identify what triggers the revert.

- Issue 2026-02-14 app-test-gap: No test target for AgentPanelApp (app-layer integration)
    Priority: Low. Area: Testing
    Description: `project.yml` only has test targets for `AgentPanelCore` and `AgentPanelCLICore`. The app delegate (auto-start at login, auto-doctor, menu wiring, focus capture) is not regression-protected by automated tests. Business logic is tested in Core, but app-layer integration (SMAppService calls, menu state, error-context auto-show) is manual-only.
    Next step: Evaluate whether an `AgentPanelAppTests` target is feasible (AppKit requires a running app host). If not, document critical app-layer paths as manual test checklist.

- Issue 2026-02-15 ax-tiebreak-residual: AX window tie-break relies on undocumented enumeration ordering
    Priority: Low. Area: Window Positioning
    Description: Duplicate-title AX window tie-break now uses enumeration index (PID ascending + kAXWindowsAttribute order) instead of CFHash. This is empirically stable but Apple does not formally document kAXWindowsAttribute ordering. If the ordering changes between calls (e.g., due to stacking order changes), windows with identical titles could still flip.
    Next step: If users report continued position flipping with duplicate-title windows, escalate to CGWindowID-based identity via CGWindowListCopyWindowInfo cross-referencing.

- Issue 2026-02-09 al-dual-window: al vscode unconditionally appends "." to code args, causing two VS Code windows
    Priority: Low. Area: Agent Layer/IDE
    Description: `al vscode` in `internal/clients/vscode/launch.go` always appends `.` (CWD) to the `code` args it constructs, so `al vscode --no-sync --new-window <path>` becomes `code --new-window <path> .` → two windows. Workaround in AgentPanel: run `al sync` (CWD = project path) then `al vscode --no-sync --new-window` with CWD = project path and no positional path (so "." maps to the repo root). This preserves Agent Layer env vars like `CODEX_HOME`.
    Next step: Fix in `conn-castle/agent-layer` (GitHub issue filed): skip appending `.` when passArgs already contains a positional arg, so path-based launches don't open two windows.
