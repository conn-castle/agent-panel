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
    Decision: AL launcher runs `al sync` (CWD = project path) then `code --new-window <projectPath>` directly, instead of using `al vscode`. Window identification uses a `// >>> agent-panel` block in `.vscode/settings.json` (see `vscodesettings` decision).
    Reason: `al vscode` unconditionally appends `.` (CWD) to the `code` args (`internal/clients/vscode/launch.go`), causing two VS Code windows.
    Tradeoffs: Loses `CODEX_HOME` env var (only needed by Codex VS Code extension). Once `al vscode` is fixed upstream (see ISSUES.md `al-dual-window`), revert to single-command launch for CODEX_HOME support.

- Decision 2026-02-10 vscodesettings: VS Code window title via settings.json block (replaces workspace files)
    Decision: Inject a `// >>> agent-panel` / `// <<< agent-panel` marker block into the project's `.vscode/settings.json` with `window.title = "AP:<id> - ..."`. Block is always inserted at the top of the file (right after `{`) with trailing comma. For SSH projects, write settings.json on the remote via SSH (read → injectBlock → base64 → write). If SSH write fails, project activation fails loudly (no workspace fallback). Doctor verifies the block exists on SSH remotes (WARN if missing).
    Reason: Eliminates overhead of separate workspace files per project and the `~/.local/state/agent-panel/vscode/` directory. Settings.json blocks coexist with Agent Layer's `// >>> agent-layer` markers since `al sync` preserves content outside its own markers.
    Tradeoffs: Trailing commas in JSONC are valid but may confuse strict JSON parsers. SSH remote write requires SSH access; unreachable SSH hosts prevent activation until connectivity/permissions are restored.

- Decision 2026-02-10 proactive-settings: Settings.json blocks written proactively on config load
    Decision: After loading config on startup, the app proactively calls `ApVSCodeSettingsManager.ensureAllSettingsBlocks(projects:)` in the background to write settings.json blocks for all projects (local via file system, SSH via SSH commands). Failures are logged at warn level and do not block config load. Launchers still write during activation as an idempotent safety net.
    Reason: Settings blocks must exist before VS Code opens the project (for reliable window identification), not just when AgentPanel activates it. Proactive writing early in app startup reduces "first activate" flakiness and keeps manual VS Code opens consistent.
    Tradeoffs: SSH write adds latency to background startup work (bounded by 10s timeout per SSH call, 2 calls per SSH project). Unreachable SSH hosts will log warnings but not block app startup.

- Decision 2026-02-11 dismisspolicy: SwitcherDismissReason and policy extracted to Core
    Decision: Moved `SwitcherDismissReason` enum and dismiss/restore policy logic from App (SwitcherPanelController) to Core (`SwitcherDismissPolicy.swift`). All types are `public`.
    Reason: Enables unit testing of dismiss semantics without an App test target. The types are pure value types with no AppKit dependency.
    Tradeoffs: Expands Core's public API surface with presentation-adjacent types. Accepted because the alternative (App test target with NSPanel mocks) is significantly more complex.

- Decision 2026-02-11 configwarn: Config.loadDefault returns ConfigLoadSuccess with warnings
    Decision: Changed `Config.loadDefault()` return type from `Result<Config, ConfigLoadError>` to `Result<ConfigLoadSuccess, ConfigLoadError>` where `ConfigLoadSuccess` carries both `config: Config` and `warnings: [ConfigFinding]`.
    Reason: WARN-severity config findings (e.g., deprecated fields) were silently dropped because the previous return type had no way to convey non-fatal warnings alongside a valid config.
    Tradeoffs: All call sites (ProjectManager, CLI handlers, App, tests) required migration to unwrap `.config` from the success value.

- Decision 2026-02-10 covgate: Coverage gate enforced via scripts/test.sh
    Decision: `scripts/test.sh` enables code coverage and enforces a 90% minimum line-coverage gate on non-UI targets (`AgentPanelCore`, `AgentPanelCLICore`) via `scripts/coverage_gate.sh`. `AgentPanelAppKit` is excluded because it contains system-level code (AX APIs, NSScreen, CGDisplay) that requires a live window server — not exercisable in CI unit tests. A repo-managed git pre-commit hook (installed via `scripts/install_git_hooks.sh`) also runs `scripts/test.sh`.
    Reason: Deterministic quality bar for core/business logic; presentation/UI code and system integration code are intentionally not gated.
    Tradeoffs: UI and AppKit target coverage is not enforced; developers must install git hooks locally (CI still enforces).

- Decision 2026-02-12 windowlayout: Window positioning uses AX APIs with Core/AppKit protocol layering
    Decision: Window positioning protocols (WindowPositioning, ScreenModeDetecting) are defined in Core using only Foundation/CG types. Concrete implementations (AXWindowPositioner, ScreenModeDetector) live in AppKit module. ProjectManager accepts them as optional init params from App/CLI callers.
    Reason: Core cannot import AppKit. Protocols with Foundation/CG types allow business logic (layout engine, position store, config validation) to stay in Core and be fully unit-testable, while AX/NSScreen code stays in AppKit.
    Tradeoffs: AppKit code (~350 lines) is not coverage-gated (requires live window server). AgentPanelAppKit excluded from coverage gate.

- Decision 2026-02-12 cascadematch: Multiple AX window matches are cascaded, not rejected
    Decision: When multiple windows match the `AP:<projectId>` title token for a bundle ID, the first window (title-sorted) gets the target frame; subsequent matches are offset by 0.5 inches down-right (cascade pattern).
    Reason: Users may have duplicate tagged windows from VS Code reload or Chrome reopens. Rejecting the positioning on multi-match would be surprising and unhelpful.
    Tradeoffs: Cascade offset is fixed at 0.5 inches regardless of window count; deeply stacked windows may overlap.

- Decision 2026-02-12 hardfaillayout: Invalid [layout] config values produce FAIL findings (hard-fail, no per-field fallback)
    Decision: If any `[layout]` value is out of range or the wrong type, it is a FAIL finding that prevents config from loading. No per-field fallback to defaults.
    Reason: Silent fallback to defaults on invalid values violates the "fail loudly" principle and can produce confusing positioning behavior.
    Tradeoffs: A single typo in `[layout]` blocks all config loading. Users must fix the value to proceed.

- Decision 2026-02-12 axprompt: Accessibility prompt via Doctor button only (not app launch)
    Decision: Do not auto-prompt for Accessibility permission on app launch. Instead, Doctor shows a "Request Accessibility" button when the check is FAIL.
    Reason: Auto-prompting on every launch is invasive UX — the system dialog is modal and disruptive, especially when the user may not need window positioning.
    Tradeoffs: Users must open Doctor to trigger the Accessibility prompt. First-time users won't be prompted until they check Doctor or try window positioning.

- Decision 2026-02-12 axvaluetype: CFGetTypeID-based AXValue type checking (not Swift conditional cast)
    Decision: Use `CFGetTypeID(obj) == AXValueGetTypeID()` to validate AXValue types before downcasting, instead of `as? AXValue`.
    Reason: Swift `as?` conditional cast always succeeds for CoreFoundation bridged types — it never returns nil for AXValue, making it useless as a type guard.
    Tradeoffs: Slightly more verbose code, but actually catches type mismatches that `as?` silently passes through.

- Decision 2026-02-12 recoverymatch: Window recovery prefers focused window, falls back to title match
    Decision: `recoverWindow()` in AXWindowPositioner first checks the app's AX focused window (via `kAXFocusedWindowAttribute`). If its title matches, uses it directly. Falls back to title enumeration only if the focused window doesn't match. `WindowRecoveryManager` calls `aerospace.focusWindow(windowId:)` before each recovery to set up the focused window.
    Reason: Duplicate-title windows (common for Chrome/VS Code) would cause the same window to be found on every recovery call. By focusing each AeroSpace window first, the AX focused window is unambiguous regardless of title.
    Tradeoffs: Recovery now changes window focus as a side effect (restored at end). Slightly more AeroSpace CLI calls (one focus per window).

- Decision 2026-02-12 recoverywm: WindowRecoveryManager is separate from ProjectManager
    Decision: Window recovery logic lives in a new `WindowRecoveryManager` class, not in ProjectManager.
    Reason: ProjectManager is already large. Recovery is orthogonal to project lifecycle (it operates on arbitrary windows, not projects). Separate class keeps responsibilities clear and testable.
    Tradeoffs: App layer must wire a second manager. Minor complexity increase.

- Decision 2026-02-10 alvscodecwd: Agent Layer VS Code launch restores CODEX_HOME without dual-window bug
    Decision: For `useAgentLayer = true`, AgentPanel runs `al sync` (CWD = project path) then launches VS Code via `al vscode --no-sync --new-window` with CWD = project path and no positional path (so "." maps to the repo root). This supersedes the `allauncher` direct-`code` workaround.
    Reason: `al vscode` sets repo-specific `CODEX_HOME` (needed by the Codex VS Code extension) and merges Agent Layer env vars, but passing an explicit path triggers the upstream dual-window bug because `al vscode` appends ".".
    Tradeoffs: Relies on `al vscode` continuing to append "."; upstream fix is still desirable so path-based launches don't open two windows.
