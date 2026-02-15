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

- Issue 2026-02-14 doctor-responsiveness: Doctor command may still freeze on non-SSH blocking calls
    Priority: Medium. Area: Doctor/Performance
    Description: SSH project checks are now parallelized (N*20s → ~20s ceiling, since each project runs two 10s-timeout SSH calls sequentially within its concurrent unit). Other blocking calls remain synchronous: login shell PATH resolution (5s timeout), AeroSpace CLI compatibility checks (up to 12s if all timeout). Full async refactor is needed for complete responsiveness.
    Next step: Profile remaining blocking calls and consider async/await refactor or progress indicators for long-running checks.

- Issue 2026-02-14 aerospace-recovery: Non-graceful recovery when AeroSpace fails
    Priority: Medium. Area: AeroSpace/Resilience
    Description: The system does not recover gracefully if the AeroSpace daemon fails or becomes unresponsive. While the circuit breaker prevents cascading timeouts, the user experience degrades significantly without an automated restart path or a robust fallback mode for window management.
    Next step: Implement a recovery strategy that can detect AeroSpace failure and attempt a restart or provide a clear fallback state for the switcher.

- Issue 2026-02-14 app-test-gap: No test target for AgentPanelApp (app-layer integration)
    Priority: Low. Area: Testing
    Description: `project.yml` only has test targets for `AgentPanelCore` and `AgentPanelCLICore`. The app delegate (auto-start at login, auto-doctor, menu wiring, focus capture) is not regression-protected by automated tests. Business logic is tested in Core, but app-layer integration (SMAppService calls, menu state, error-context auto-show) is manual-only.
    Next step: Evaluate whether an `AgentPanelAppTests` target is feasible (AppKit requires a running app host). If not, document critical app-layer paths as manual test checklist.

- Issue 2026-02-12 ax-tiebreak: Duplicate-title AX window ordering may flip between enumerations
    Priority: Low. Area: Window Positioning
    Description: When multiple AX windows share identical titles, the secondary sort key `CFHash(AXUIElement)` is not guaranteed stable across independent enumerations. This could cause the "primary" window to flip between two identically-titled windows on successive activations.
    Next step: If users report window position flipping, consider adding a more stable identity (e.g., AX window ID attribute or process-scoped index).

- Issue 2026-02-12 aerospace-focus-crash: AeroSpace crashes with "MacWindow is already unbound" during FocusCommand
    Priority: Medium. Area: AeroSpace/Upstream
    Description: AeroSpace runtime error `MacWindow is already unbound` triggered by concurrent CLI commands while floating switcher panel is visible. AgentPanel mitigations in place: (1) Doctor refresh deferred until after switcher session ends (`onSessionEnded` callback), (2) `AeroSpaceCircuitBreaker` trips on first timeout and fails fast for 30s cooldown, preventing ~90s cascade. Root cause is upstream — AeroSpace socket server concurrent unbind/rebind race.
    Next step: File upstream issue with AeroSpace repo.

- Issue 2026-02-09 al-dual-window: al vscode unconditionally appends "." to code args, causing two VS Code windows
    Priority: Low. Area: Agent Layer/IDE
    Description: `al vscode` in `internal/clients/vscode/launch.go` always appends `.` (CWD) to the `code` args it constructs, so `al vscode --no-sync --new-window <path>` becomes `code --new-window <path> .` → two windows. Workaround in AgentPanel: run `al sync` (CWD = project path) then `al vscode --no-sync --new-window` with CWD = project path and no positional path (so "." maps to the repo root). This preserves Agent Layer env vars like `CODEX_HOME`.
    Next step: Fix in `conn-castle/agent-layer` (GitHub issue filed): skip appending `.` when passArgs already contains a positional arg, so path-based launches don't open two windows.

- Issue 2026-02-09 fish-shell-path: Login shell PATH resolution may not work with fish shell
    Priority: Low. Area: System/PATH
    Description: `runLoginShellCommand` uses `$SHELL -l -c <command>` to resolve the login shell PATH. `$SHELL` is validated as an absolute path (non-absolute values fall back to `/bin/zsh`). Fish shell does not support the `-c` flag in the same way as bash/zsh. Users with `$SHELL=/usr/local/bin/fish` may get nil PATH resolution (safe — falls back to standard paths + process PATH).
    Next step: If a fish user reports missing executables in child processes, add fish-specific PATH resolution (`fish -l -c 'echo $PATH'` uses space-separated entries, not colon-separated).
