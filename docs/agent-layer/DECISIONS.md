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

- Decision 2026-02-09 allauncher: Agent Layer VS Code launch uses `al sync` + `al vscode --no-sync --new-window`
    Decision: For `useAgentLayer = true`, AgentPanel runs `al sync` (CWD = project path) then `al vscode --no-sync --new-window` (CWD = project path, no positional path so "." maps to repo root). This preserves Agent Layer env vars like `CODEX_HOME` while avoiding the upstream dual-window bug (`al vscode` appends "." to `code` args in `internal/clients/vscode/launch.go`). Window identification uses a `// >>> agent-panel` block in `.vscode/settings.json` (see `vscodesettings` decision).
    Reason: Direct `code --new-window <path>` (original workaround) lost `CODEX_HOME`. Using `al vscode` without a positional path avoids the dual-window bug while keeping Agent Layer env vars.
    Tradeoffs: Relies on `al vscode` continuing to append "."; upstream fix is still desirable so path-based launches don't open two windows (see ISSUES.md `al-dual-window`).

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

- Decision 2026-02-13 autostart: Auto-start at login uses config as source of truth
    Decision: `[app] autoStartAtLogin` in `config.toml` is the authoritative source for launch-at-login state. The menu toggle writes back to config. `SMAppService.mainApp` registers/unregisters the login item.
    Reason: Config-as-truth avoids split-brain between the login item registration state and the config file. The config is always the canonical state.
    Tradeoffs: Menu toggle must write to disk (config file) on every change. If config write fails, the toggle reverts.

- Decision 2026-02-14 peacock: VS Code color differentiation via Peacock extension
    Decision: Replaced direct `workbench.colorCustomizations` injection (6 keys) with a single `"peacock.color": "#RRGGBB"` key in the settings.json block. The Peacock VS Code extension (`johnpapa.vscode-peacock`) reads this key and applies color across title bar, activity bar, and status bar. Doctor warns (not fails) if Peacock is not installed.
    Reason: Peacock provides better color theming with a single key instead of 6, handles foreground contrast automatically, and is a well-maintained community extension.
    Tradeoffs: Requires an additional VS Code extension install. Projects without Peacock installed will see the key in settings but no color effect (graceful degradation).

- Decision 2026-02-14 autostart-rollback: Config write failure rolls back SMAppService toggle
    Decision: When the "Launch at Login" toggle succeeds at the SMAppService level but fails to write back to config.toml, the SMAppService toggle is undone (re-register or unregister) and the menu title is reset to "Launch at Login" (not "(save failed)").
    Reason: Avoids split-brain between SMAppService state and config.toml as the source of truth.
    Tradeoffs: None significant; the rollback is best-effort (try?).

- Decision 2026-02-14 workspacetab: Workspace-scoped window cycling via native AeroSpace focus commands
    Decision: Use AeroSpace's native `focus --boundaries workspace --boundaries-action wrap-around-the-workspace dfs-next`/`dfs-prev` bound to Option-Tab / Option-Shift-Tab in the managed `aerospace-safe.toml` template. No custom CLI subcommand needed.
    Reason: AeroSpace's DFS-order focus natively includes floating windows (unless `--ignore-floating` is set). A custom `ap cycle-focus` CLI was considered but rejected because AeroSpace's `exec-and-forget` would need `ap` on PATH, which is brittle for GUI apps.
    Tradeoffs: DFS order is not identical to macOS Cmd-Tab (MRU order), but provides deterministic, predictable cycling within a workspace. Config is now auto-updated on startup with user sections preserved.

- Decision 2026-02-14 compatvaluefix: Compatibility check validates flags, not flag values
    Decision: Removed `wrap-around-the-workspace` from the `focus` command compatibility check. The check verifies `--boundaries-action` (the flag) is supported; `wrap-around-the-workspace` is a *value* for that flag and is not listed in `aerospace focus --help`.
    Reason: The help text shows `<action>` placeholder, not enumerated values. The value works at runtime (exit code 0) but string-matching against help output produces a false-negative FAIL.
    Tradeoffs: If a future AeroSpace version removes `wrap-around-the-workspace` as a valid value, the compatibility check won't catch it. Acceptable because the keybinding would fail at runtime with an error, which is observable.

- Decision 2026-02-14 chromecolordefer: Chrome visual differentiation deferred permanently to BACKLOG
    Decision: Removed `chrome-color` from Phase 7 and moved to BACKLOG. Chrome has no clean programmatic injection point for window color theming.
    Reason: Unlike VS Code (which has Peacock extension reading a single settings.json key), Chrome provides no equivalent mechanism. Chrome profiles could work but require complex profile management. A custom Chrome extension is possible but out of scope for polish work.
    Tradeoffs: Chrome windows have no visual color correlation with their project. Users must rely on tab content to identify project Chrome windows.

- Decision 2026-02-14 circuitbreaker: AeroSpace CLI circuit breaker prevents timeout cascades
    Decision: `AeroSpaceCircuitBreaker` (process-wide shared instance) sits between `ApAeroSpace` and `CommandRunning`. All `aerospace` CLI calls go through `runAerospace()`, which checks the breaker before spawning a process. On timeout, the breaker trips to "open" state for a 30s cooldown; subsequent calls fail immediately with a descriptive error. `start()` resets the breaker after a fresh AeroSpace launch.
    Reason: When AeroSpace crashes or its socket becomes unresponsive, every CLI call times out at 5s. With 15-20 calls in a Doctor check, this creates a ~90s freeze. The circuit breaker detects the first timeout and immediately fails the rest.
    Tradeoffs: A single transient timeout trips the breaker for 30s, potentially blocking legitimate calls. After cooldown, the next call acts as a probe to re-verify connectivity.

- Decision 2026-02-14 doctorcolor: Doctor CLI output uses ANSI color codes with TTY auto-detection
    Decision: `DoctorReport.rendered(colorize:)` wraps severity labels (PASS/WARN/FAIL) in ANSI escape codes when `colorize` is true. The CLI detects TTY via `isatty(STDOUT_FILENO)` and respects the `NO_COLOR` environment variable. Default is no color (backward compatible).
    Reason: Color-coded severity improves scan-ability of Doctor output. TTY detection ensures piped output and `NO_COLOR` convention work correctly.
    Tradeoffs: None significant; color is purely additive and opt-in via TTY detection.

- Decision 2026-02-14 aeroconfigown: AeroSpace config full ownership with versioned template and user sections
    Decision: AgentPanel fully owns `~/.aerospace.toml` via a versioned template (`# ap-config-version: N`). On startup, `ensureUpToDate()` compares the installed config version against the template version and auto-updates if stale, preserving user content between `# >>> user-keybindings` / `# <<< user-keybindings` and `# >>> user-config` / `# <<< user-config` markers. After a successful update, AeroSpace is reloaded via `aerospace reload-config` so the running process picks up changes. Pre-migration configs (no version/markers) are updated with default placeholders. Missing template version is a hard failure (fail loudly).
    Reason: Previous approach only wrote the config once during onboarding. Template changes (new keybindings, config options) left users on stale configs with no auto-update path. Doctor detected stale keybindings but the fix was manual.
    Tradeoffs: Users must place custom config within the marker sections; content outside markers is overwritten on update. The version bump requires incrementing the `# ap-config-version` line in `aerospace-safe.toml`.

- Decision 2026-02-14 sshparallel: Doctor SSH project checks run concurrently via GCD
    Decision: SSH project health checks (path existence + settings block) run in parallel using `DispatchQueue.concurrentPerform`. Local project checks remain sequential (fast). Thread-safe findings accumulation via `NSLock`.
    Reason: Sequential SSH checks caused N*20s blocking for N SSH projects (two 10s-timeout calls per project). Parallelization reduces worst-case to ~20s regardless of project count (each project's two calls still run sequentially within its concurrent unit).
    Tradeoffs: Same-severity SSH findings appear in non-deterministic order (acceptable — findings are sorted by severity in rendering, and tests validate presence not order). Test doubles must be thread-safe.

- Decision 2026-02-14 floatingfocusfix: Native Swift window cycling replaces AeroSpace dfs-next/dfs-prev
    Decision: Option-Tab / Option-Shift-Tab is handled natively in Swift via `WindowCycler` (Core) and `FocusCycleHotkeyManager` (App, Carbon API). WindowCycler calls `focusedWindow()` → `listWindowsWorkspace()` → `focusWindow()` to cycle through all workspace windows with wrapping. AeroSpace config template (v3) no longer contains alt-tab keybindings; Doctor keybinding check removed.
    Reason: AeroSpace's DFS traversal (`rootTilingContainer.allLeafWindowsRecursive`) does not include floating windows, and all windows are floating in AgentPanel's managed config. An intermediate script-based approach was rejected because Swift code is easier to test, maintain, and debug than shell scripts invoked via `exec-and-forget`.
    Tradeoffs: Carbon global hotkeys require the app to be running (acceptable — AgentPanel is a background agent). Supersedes decisions `workspacetab` and the intermediate script approach.
