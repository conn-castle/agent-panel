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
    Description: `al vscode` in `internal/clients/vscode/launch.go` always appends `.` (CWD) to the `code` args it constructs, so `al vscode --no-sync --new-window <path>` becomes `code --new-window <path> .` → two windows. Workaround in AgentPanel: run `al sync` (CWD = project path) then `al vscode --no-sync --new-window` with CWD = project path and no positional path (so "." maps to the repo root). This preserves Agent Layer env vars like `CODEX_HOME`.
    Next step: Fix in `conn-castle/agent-layer` (GitHub issue filed): skip appending `.` when passArgs already contains a positional arg, so path-based launches don't open two windows.


- Issue 2026-02-09 fish-shell-path: Login shell PATH resolution may not work with fish shell
    Priority: Low. Area: System/PATH
    Description: `runLoginShellCommand` uses `$SHELL -l -c <command>` to resolve the login shell PATH. `$SHELL` is validated as an absolute path (non-absolute values fall back to `/bin/zsh`). Fish shell does not support the `-c` flag in the same way as bash/zsh. Users with `$SHELL=/usr/local/bin/fish` may get nil PATH resolution (safe — falls back to standard paths + process PATH).
    Next step: If a fish user reports missing executables in child processes, add fish-specific PATH resolution (`fish -l -c 'echo $PATH'` uses space-separated entries, not colon-separated).

- Issue 2026-02-09 doctor-color-output: Color code the Doctor CLI output
    Priority: Low. Area: Doctor/CLI
    Description: The Doctor CLI output is currently plain text. Adding color (e.g., Red for FAIL, Yellow for WARN, Green for OK) would significantly improve readability and quick scanning of health checks.
    Next step: Integrate a color-coding utility into the Doctor report rendering logic.



