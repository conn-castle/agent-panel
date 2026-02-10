# Decisions

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
A rolling log of important, non-obvious decisions that materially affect future work (constraints, deferrals, irreversible tradeoffs). Only record decisions that future developers/agents would not learn just by reading the code. Do not log routine choices or standard best-practice decisions; if it is obvious from the code, leave it out.

## Format
- Keep entries brief and durable (avoid restating obvious defaults).
- Keep the oldest decisions near the top and add new entries at the bottom.
- Insert entries under `<!-- ENTRIES START -->`.
- Line 1 starts with `- Decision YYYY-MM-DD <id>:` and a short title.
- Lines 2–4 are indented by **4 spaces** and use `Key: Value`.
- Keep **exactly one blank line** between entries.
- If a decision is superseded, add a new entry describing the change (do not delete history unless explicitly asked).

### Entry template
```text
- Decision YYYY-MM-DD abcdef: Short title
    Decision: <what was chosen>
    Reason: <why it was chosen>
    Tradeoffs: <what is gained and what is lost>
```

## Decision Log

<!-- ENTRIES START -->

- Decision 2026-02-03 brewonly: Homebrew-only distribution
    Decision: Both AgentPanel and AeroSpace are installed via Homebrew only; direct-download installs (zip/dmg) are not supported.
    Reason: Deterministic installs/upgrades, scriptable onboarding and Doctor automation, and reduced distribution surface area.
    Tradeoffs: Users without Homebrew cannot install or onboard. Any future direct-download path requires signing/notarization + updater work.

- Decision 2026-02-03 guipath: GUI apps and child processes require PATH augmentation
    Decision: Use `ExecutableResolver` for finding executables and `ApSystemCommandRunner` for propagating an augmented PATH to child processes. Both merge standard search paths with the user's login shell PATH (via `$SHELL -l -c 'echo $PATH'`, validated as absolute path, falls back to `/bin/zsh`).
    Reason: macOS GUI apps launched via Finder/Dock inherit a minimal PATH missing Homebrew and user additions. Child processes (e.g., `al` calling `code`) inherit the same minimal PATH and fail. `/usr/bin/env` is not viable.
    Tradeoffs: Login shell spawn at init (~50ms, cached). Non-POSIX shells (fish) may not work (safe fallback to standard paths).

- Decision 2026-02-08 chrometabs: Chrome has no scriptable tab-pinning API
    Decision: Use "always-open" tabs (regular tabs, leftmost position) instead of Chrome pinned tabs.
    Reason: Chrome tab pinning is only available via user interaction (right-click → Pin). Neither AppleScript nor remote debugging can pin tabs programmatically.
    Tradeoffs: Tabs appear as regular tabs; users must manually pin if desired.

- Decision 2026-02-08 snaptruth: Snapshot-is-truth for Chrome tab persistence
    Decision: Save all captured Chrome tab URLs verbatim on close (no filtering). Restore snapshot directly on activate. Always-open + default tabs are only used for cold start (no snapshot). Capture failures preserve the existing snapshot; empty capture (window gone) deletes it.
    Reason: Exact-match URL filtering is unreliable because Chrome redirects URLs (e.g., `todoist.com/` → `todoist.com/app/today`), git remote URLs differ from web URLs, and other dynamic URL changes.
    Tradeoffs: Snapshot may overlap with always-open config; harmless since the snapshot IS the intended tab state.

- Decision 2026-02-09 allauncher: Agent Layer launcher uses `al sync` + direct `code` (two-step workaround)
    Decision: AL launcher runs `al sync` (CWD = project path) then `code --new-window <workspace>` directly, instead of using `al vscode`.
    Reason: `al vscode` unconditionally appends `.` (CWD) to the `code` args (`internal/clients/vscode/launch.go`), causing two VS Code windows.
    Tradeoffs: Loses `CODEX_HOME` env var (only needed by Codex VS Code extension). Once `al vscode` is fixed upstream (see ISSUES.md `al-dual-window`), revert to single-command launch for CODEX_HOME support.

- Decision 2026-02-10 covgate: Coverage gate enforced via scripts/test.sh
    Decision: `scripts/test.sh` enables code coverage and enforces a 90% minimum line-coverage gate on non-UI targets (`AgentPanelCore`, `AgentPanelCLICore`, `AgentPanelAppKit`) via `scripts/coverage_gate.sh`. A repo-managed git pre-commit hook (installed via `scripts/install_git_hooks.sh`) also runs `scripts/test.sh`.
    Reason: Deterministic quality bar for core/business logic; presentation/UI code is intentionally not gated.
    Tradeoffs: UI target coverage is not enforced; developers must install git hooks locally (CI still enforces).
