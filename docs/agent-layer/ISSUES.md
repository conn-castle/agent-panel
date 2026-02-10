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

- Issue 2026-02-09 al-dual-window: al vscode unconditionally appends "." to code args, causing two VS Code windows
    Priority: Low. Area: Agent Layer/IDE
    Description: `al vscode` in `internal/clients/vscode/launch.go` always appends `.` (CWD) to the `code` args it constructs, so `al vscode --no-sync --new-window workspace.code-workspace` becomes `code --new-window workspace.code-workspace .` → two windows. Workaround implemented: AgentPanel now runs `al sync` (CWD = project path) then `code --new-window <workspace>` directly. This loses `CODEX_HOME` env var that `al vscode` normally sets (only needed by Codex VS Code extension).
    Next step: Fix in `conn-castle/agent-layer` (GitHub issue filed): skip appending `.` when passArgs already contains a positional arg. Once fixed, consider reverting to `al vscode` for CODEX_HOME support.

- Issue 2026-02-09 activation-error-invisible: Activation errors invisible when panel closes during async launch
    Priority: High. Area: App/Switcher UX
    Description: During `selectProject`, Chrome's new window steals focus from the switcher panel, triggering `windowDidResignKey` → `dismiss(reason: .windowClose)`. If the subsequent VS Code launch fails, the error status message is set on an already-dismissed panel, so the user sees no indication of failure.
    Next step: Suppress `windowDidResignKey` dismissal while an activation task is in progress (add an `isActivating` guard). Alternatively, surface the error via a notification or menu bar indicator.

- Issue 2026-02-09 fish-shell-path: Login shell PATH resolution may not work with fish shell
    Priority: Low. Area: System/PATH
    Description: `runLoginShellCommand` uses `$SHELL -l -c <command>` to resolve the login shell PATH. `$SHELL` is validated as an absolute path (non-absolute values fall back to `/bin/zsh`). Fish shell does not support the `-c` flag in the same way as bash/zsh. Users with `$SHELL=/usr/local/bin/fish` may get nil PATH resolution (safe — falls back to standard paths + process PATH).
    Next step: If a fish user reports missing executables in child processes, add fish-specific PATH resolution (`fish -l -c 'echo $PATH'` uses space-separated entries, not colon-separated).

- Issue 2026-02-09 doctor-unrecognized-config: Doctor should fail on unrecognized config.toml entries
    Priority: Medium. Area: Doctor/Config
    Description: Currently, the Doctor does not flag unrecognized keys in `config.toml`. It should fail verification if the configuration contains unknown entries to prevent silent typos or configuration errors.
    Next step: Update the configuration loader or Doctor check to validate that all keys in `config.toml` are known schemas.

- Issue 2026-02-09 doctor-summary-counts: Summarize Doctor failures and warnings with counts
    Priority: Low. Area: Doctor/CLI
    Description: The Doctor output lacks a high-level summary. It should provide a concise count of total failures and warnings at the end of the report to give the user a quick health overview.
    Next step: Update the `DoctorReport` or the CLI rendering logic to track and print failure/warning counts.

- Issue 2026-02-09 doctor-color-output: Color code the Doctor CLI output
    Priority: Low. Area: Doctor/CLI
    Description: The Doctor CLI output is currently plain text. Adding color (e.g., Red for FAIL, Yellow for WARN, Green for OK) would significantly improve readability and quick scanning of health checks.
    Next step: Integrate a color-coding utility into the Doctor report rendering logic.

- Issue 2026-02-09 doctor-focus: Closing Doctor window does not restore previous focus
    Priority: Medium. Area: UI/UX
    Description: When the Doctor window is closed, the application does not restore focus to the window that was focused before the Doctor was opened. It should return focus to the previous application/window to ensure a smooth workflow.
    Next step: Capture the currently focused window before showing the Doctor window and restore it upon closing.

- Issue 2026-02-08 cli-runner-tests: CLI runner tests missing for new ProjectManager commands
    Priority: Medium. Area: CLI Tests
    Description: `ApCLIRunnerTests` only covers `version`, `doctor`, and `help` commands. The new `show-config`, `list-projects`, `select-project`, `close-project`, and `return` commands lack CLI-runner-level tests validating success and failure paths through the ProjectManager bridge.
    Next step: Add CLI runner tests for each new command with mock ProjectManager, covering both success and error cases (including the async semaphore bridge for `select-project`).

- Issue 2026-02-07 switcher-lifecycle-tests: Switcher dismiss/restore lifecycle lacks direct tests
    Priority: High. Area: App/Switcher Tests
    Description: Recent regressions involved `windowClose`/termination-triggered focus restore and app activation fallback behavior, but there is no dedicated test target validating switcher dismiss semantics.
    Next step: Add App-layer tests (or extract testable policy helpers) covering `dismiss` reason handling and prohibiting app-activation fallback on project handoff/termination paths.
    Notes: Existing ProjectManager tests do not cover AppKit panel lifecycle paths.

- Issue 2026-02-05 pm-tests: ProjectManager coverage is still incomplete
    Priority: High. Area: Tests
    Description: `ProjectManager` still lacks direct operation tests for config loading, sorting, recency persistence, and the full activation path; current tests cover workspace-state queries, chrome-tab close paths, and focus stack behavior.
    Next step: Add targeted tests for load/sort/recency and the full selectProject activation flow, including single-phase Chrome launch with resolved URLs.
    Notes: Chrome tab close tests added (2026-02-08). Focus stack tests added (2026-02-09) covering FocusStack unit tests and ProjectManager focus integration (exit-project-space semantic, project-to-project filtering, stale entry handling, close/reopen cycles). Activation-path tests (deferred URL resolution, Chrome launch fallback) still needed.

- Issue 2026-02-04 config-warn: Config warnings not surfaced to UI
    Priority: Medium. Area: Config/UX
    Description: `Config.loadDefault()` returns `Result<Config, ConfigLoadError>` which cannot convey warnings. If config is valid but has warnings (e.g., deprecated fields), they are silently dropped.
    Next step: Either change return type to include warnings, or add a separate `Config.loadDefaultWithWarnings()` method that returns warnings alongside the config.
    Notes: SwitcherPanelController clears status on success, so even if warnings were returned they'd need explicit handling.

- Issue 2026-02-03 doctorsev: Doctor VS Code/Chrome checks should FAIL when a project needs them
    Priority: Medium. Area: Doctor
    Description: VS Code and Chrome checks are currently WARN. They should be FAIL if any configured project would use them (same logic as the agent-layer CLI check).
    Next step: Add project config fields to specify IDE/browser requirements, then check those fields in Doctor and fail if the required app is missing.
    Notes: Blocked until project config schema includes IDE/browser requirements.
