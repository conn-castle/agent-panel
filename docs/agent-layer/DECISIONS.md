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

- Decision 2026-02-03 guipath: GUI apps and child processes require PATH augmentation
    Decision: Use `ExecutableResolver` for finding executables and `ApSystemCommandRunner` for propagating an augmented PATH to child processes. Both merge standard search paths with the user's login shell PATH (via `$SHELL -l -c <command>`, validated as absolute path, falls back to `/bin/zsh`). Fish shell is detected via `$SHELL` path suffix and uses `string join : $PATH` for colon-delimited output.
    Reason: macOS GUI apps launched via Finder/Dock inherit a minimal PATH missing Homebrew and user additions. Child processes (e.g., `al` calling `code`) inherit the same minimal PATH and fail. `/usr/bin/env` is not viable.
    Tradeoffs: Login shell spawn at init (~50ms, cached). Shells other than bash, zsh, and fish are untested (safe fallback to standard paths).

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

- Decision 2026-02-10 proactive-settings: Settings.json blocks written proactively on config load (superseded by `reactsettings`)
    Decision: After loading config on startup, the app proactively calls `ApVSCodeSettingsManager.ensureAllSettingsBlocks(projects:)` in the background to write settings.json blocks for all projects (local via file system, SSH via SSH commands). Failures are logged at warn level and do not block config load. Launchers still write during activation as an idempotent safety net.
    Reason: Settings blocks must exist before VS Code opens the project (for reliable window identification), not just when AgentPanel activates it. Proactive writing early in app startup reduces "first activate" flakiness and keeps manual VS Code opens consistent.
    Tradeoffs: SSH write adds latency to background startup work (bounded by 10s timeout per SSH call, 2 calls per SSH project). Unreachable SSH hosts will log warnings but not block app startup.

- Decision 2026-02-10 covgate: Coverage gate enforced via scripts/test.sh
    Decision: `scripts/test.sh` enables code coverage and enforces a 90% minimum line-coverage gate on non-UI targets (`AgentPanelCore`, `AgentPanelCLICore`) via `scripts/coverage_gate.sh`. `AgentPanelAppKit` is excluded because it contains system-level code (AX APIs, NSScreen, CGDisplay) that requires a live window server — not exercisable in CI unit tests. A repo-managed git pre-commit hook (installed via `scripts/install_git_hooks.sh`) also runs `scripts/test.sh`.
    Reason: Deterministic quality bar for core/business logic; presentation/UI code and system integration code are intentionally not gated.
    Tradeoffs: UI and AppKit target coverage is not enforced; developers must install git hooks locally (CI still enforces).

- Decision 2026-02-12 windowlayout: Window positioning uses AX APIs with Core/AppKit protocol layering
    Decision: Window positioning protocols (WindowPositioning, ScreenModeDetecting) are defined in Core using only Foundation/CG types. Concrete implementations (AXWindowPositioner, ScreenModeDetector) live in AppKit module. ProjectManager accepts them as optional init params from App/CLI callers.
    Reason: Core cannot import AppKit. Protocols with Foundation/CG types allow business logic (layout engine, position store, config validation) to stay in Core and be fully unit-testable, while AX/NSScreen code stays in AppKit.
    Tradeoffs: AppKit code (~350 lines) is not coverage-gated (requires live window server). AgentPanelAppKit excluded from coverage gate.

- Decision 2026-02-12 axprompt: Accessibility prompt via Doctor button only (not app launch)
    Decision: Do not auto-prompt for Accessibility permission on app launch. Instead, Doctor shows a "Request Accessibility" button when the check is FAIL.
    Reason: Auto-prompting on every launch is invasive UX — the system dialog is modal and disruptive, especially when the user may not need window positioning.
    Tradeoffs: Users must open Doctor to trigger the Accessibility prompt. First-time users won't be prompted until they check Doctor or try window positioning.

- Decision 2026-02-13 autostart: Auto-start at login uses config as source of truth
    Decision: `[app] autoStartAtLogin` in `config.toml` is the authoritative source for launch-at-login state. The menu toggle writes back to config. `SMAppService.mainApp` registers/unregisters the login item.
    Reason: Config-as-truth avoids split-brain between the login item registration state and the config file. The config is always the canonical state.
    Tradeoffs: Menu toggle must write to disk (config file) on every change. If config write fails, the toggle reverts.

- Decision 2026-02-14 peacock: VS Code color differentiation via Peacock extension
    Decision: Replaced direct `workbench.colorCustomizations` injection (6 keys) with a single `"peacock.color": "#RRGGBB"` key in the settings.json block. The Peacock VS Code extension (`johnpapa.vscode-peacock`) reads this key and applies color across title bar, activity bar, and status bar. Doctor warns (not fails) if Peacock is not installed.
    Reason: Peacock provides better color theming with a single key instead of 6, handles foreground contrast automatically, and is a well-maintained community extension.
    Tradeoffs: Requires an additional VS Code extension install. Projects without Peacock installed will see the key in settings but no color effect (graceful degradation).

- Decision 2026-02-14 chromecolordefer: Chrome visual differentiation deferred permanently to BACKLOG
    Decision: Removed `chrome-color` from Phase 7 and moved to BACKLOG. Chrome has no clean programmatic injection point for window color theming.
    Reason: Unlike VS Code (which has Peacock extension reading a single settings.json key), Chrome provides no equivalent mechanism. Chrome profiles could work but require complex profile management. A custom Chrome extension is possible but out of scope for polish work.
    Tradeoffs: Chrome windows have no visual color correlation with their project. Users must rely on tab content to identify project Chrome windows.

- Decision 2026-02-14 circuitbreaker: AeroSpace CLI circuit breaker prevents timeout cascades
    Decision: `AeroSpaceCircuitBreaker` (process-wide shared instance) sits between `ApAeroSpace` and `CommandRunning`. All `aerospace` CLI calls go through `runAerospace()`, which checks the breaker before spawning a process. On timeout, the breaker trips to "open" state for a 30s cooldown; subsequent calls fail immediately with a descriptive error. `start()` resets the breaker after a fresh AeroSpace launch.
    Reason: When AeroSpace crashes or its socket becomes unresponsive, every CLI call times out at 5s. With 15-20 calls in a Doctor check, this creates a ~90s freeze. The circuit breaker detects the first timeout and immediately fails the rest.
    Tradeoffs: A single transient timeout trips the breaker for 30s, potentially blocking legitimate calls. After cooldown, the next call acts as a probe to re-verify connectivity.

- Decision 2026-02-14 aeroconfigown: AeroSpace config full ownership with versioned template and user sections
    Decision: AgentPanel fully owns `~/.aerospace.toml` via a versioned template (`# ap-config-version: N`). On startup, `ensureUpToDate()` compares the installed config version against the template version and auto-updates if stale, preserving user content between `# >>> user-keybindings` / `# <<< user-keybindings` and `# >>> user-config` / `# <<< user-config` markers. After a successful update, AeroSpace is reloaded via `aerospace reload-config` so the running process picks up changes. Pre-migration configs (no version/markers) are updated with default placeholders. Missing template version is a hard failure (fail loudly).
    Reason: Previous approach only wrote the config once during onboarding. Template changes (new keybindings, config options) left users on stale configs with no auto-update path. Doctor detected stale keybindings but the fix was manual.
    Tradeoffs: Users must place custom config within the marker sections; content outside markers is overwritten on update. The version bump requires incrementing the `# ap-config-version` line in `aerospace-safe.toml`.

- Decision 2026-02-14 floatingfocusfix: Native Swift window cycling replaces AeroSpace dfs-next/dfs-prev
    Decision: Option-Tab / Option-Shift-Tab is handled natively in Swift via `WindowCycler` (Core) and `FocusCycleHotkeyManager` (App, Carbon API). WindowCycler calls `focusedWindow()` → `listWindowsWorkspace()` → `focusWindow()` to cycle through all workspace windows with wrapping. AeroSpace config template (v3) no longer contains alt-tab keybindings; Doctor keybinding check removed.
    Reason: AeroSpace's DFS traversal (`rootTilingContainer.allLeafWindowsRecursive`) does not include floating windows, and all windows are floating in AgentPanel's managed config. An intermediate script-based approach was rejected because Swift code is easier to test, maintain, and debug than shell scripts invoked via `exec-and-forget`.
    Tradeoffs: Carbon global hotkeys require the app to be running (acceptable — AgentPanel is a background agent). Supersedes decisions `workspacetab` and the intermediate script approach.

- Decision 2026-02-15 autorecovery: Auto-recovery restarts AeroSpace when circuit breaker trips on a crashed process
    Decision: When `runAerospace()` finds the circuit breaker open, it checks if AeroSpace is still running via `RunningApplicationChecking`. If the process is dead, it automatically calls `start()` to restart AeroSpace and retries the original command. Max 2 recovery attempts per breaker trip. Recovery state tracked on `AeroSpaceCircuitBreaker` (thread-safe). Doctor does not get auto-recovery (processChecker is nil) so it reports the actual problem. Main-thread callers get immediate breaker error with fire-and-forget async recovery in the background; off-main callers recover synchronously and retry.
    Reason: The most common AeroSpace failure mode is a crash (process dies). Auto-recovery makes the system self-healing for this case without user intervention. Hangs (process alive but unresponsive) are left to the existing cooldown-and-probe mechanism.
    Tradeoffs: Off-main recovery adds up to ~10s latency per attempt (open + readiness poll). Main-thread callers fail fast (0ms) but must wait for background recovery to take effect on the next call. If AeroSpace repeatedly crashes, recovery stops after 2 attempts until a manual restart or the breaker cooldown resets naturally.

- Decision 2026-02-15 fishshell: Fish shell PATH resolution via `string join : $PATH`
    Decision: `ExecutableResolver.resolveLoginShellPath()` detects fish shell via `$SHELL` path suffix (`hasSuffix("/fish")`) and uses `string join : $PATH` instead of `echo $PATH`. The `string` builtin (fish 2.3.0+, 2016) emits colon-separated output natively, preserving the colon-separated contract of `resolveLoginShellPath()`.
    Reason: Fish shell's `echo $PATH` emits space-separated entries, which the downstream consumer (`buildAugmentedEnvironment`) splits on `:`, producing one invalid entry. Using a fish-native command avoids post-hoc parsing.
    Tradeoffs: False positive requires a non-fish binary at a path ending in `/fish` — extremely narrow. Most likely `string join` is not found (exit 127) and `runLoginShellCommand` returns nil (same safe fallback). In the unlikely case the binary exits 0 with non-empty output, the output is accepted as a PATH string; invalid entries are harmless noise since standard paths and process PATH are always present.

- Decision 2026-02-15 peacockanchor: workbench.colorCustomizations anchor in agent-panel block
    Decision: When a project has a color, the agent-panel settings.json block now includes `"workbench.colorCustomizations": {}` as an anchor. On re-injection, existing Peacock-written content inside that object is extracted and preserved. Trailing commas are added only when content follows the block (not when the block is the last element in the JSON).
    Reason: Peacock writes `workbench.colorCustomizations` via VS Code's config API, which appends the key after the last JSON property. If the last property is inside the `// >>> agent-layer` block, Peacock's colors land there and get stripped when `al sync` runs. The anchor ensures Peacock writes in-place inside the agent-panel block (safe from agent-layer).
    Tradeoffs: Settings.json blocks with color now have 3 properties instead of 2. Brace-depth parsing for extraction is basic (no string-aware escaping) but sufficient since Peacock only writes hex color values.

- Decision 2026-02-15 dualsignal: Workspace focus verification uses dual-signal check
    Decision: `ensureWorkspaceFocused` now calls `focusWorkspace` (summon-workspace) before accepting verification, and verifies with two signals: `listWorkspacesWithFocus` reports target focused AND `focusedWindow().workspace` equals the target. Previously, `listWorkspacesWithFocus` alone could return true without summoning the workspace to the current monitor.
    Reason: AeroSpace can report a workspace as "focused" in its model while the workspace is on a different macOS desktop space. The single-signal check could skip the summon path, leaving the user on the wrong space.
    Tradeoffs: `focusWorkspace` is always called at least once per activation (even if already on the correct workspace). This is a no-op in practice and adds negligible latency (<50ms). The `focusedWindow()` call adds one extra AeroSpace CLI invocation per poll iteration.

- Decision 2026-02-15 recoverylayout: Window recovery uses computed layout, not saved positions
    Decision: `recoverWorkspaceWindows` applies layout-aware positioning for project workspaces (`ap-<projectId>`) using `WindowLayoutEngine.computeLayout()` with current config. Saved positions from `WindowPositionStore` are deliberately ignored during recovery.
    Reason: Recovery is a "repair to known-good baseline" operation. Saved positions can be stale, misaligned, or the cause of the problem being recovered from. Computed layout from config provides a deterministic, canonical baseline.
    Tradeoffs: Users who had manually positioned windows and then recover will get the computed default layout, not their custom positions. This is the intended behavior — recovery is a reset, not a restore.

- Decision 2026-02-16 reactsettings: Settings blocks written reactively on config change via onProjectsChanged
    Decision: Replaced the startup-only `VSCodeSettingsBlocks.ensureAll` call with a `ProjectManager.onProjectsChanged` callback that fires whenever `loadConfig()` detects the project list has changed. The App layer wires this callback to run `ensureAll` in the background. Fires on first load (nil → projects) and on subsequent reloads when the project list differs.
    Reason: The previous approach only wrote settings blocks at app startup. Projects added to config while the app was running never got their settings.json block written, causing Doctor to warn and activation to fail with "content has no opening '{'".
    Tradeoffs: The callback fires synchronously within `loadConfig()` (before the return), so the handler must dispatch to a background queue for SSH writes. Launchers still write during activation as an idempotent safety net.

- Decision 2026-02-16 workspaceretry: Switcher auto-retries workspace state on circuit breaker recovery
    Decision: When `refreshWorkspaceState()` fails during `show()`, the switcher displays "Recovering AeroSpace..." and schedules a main-thread `DispatchSourceTimer` (2s interval, max 5 retries). On success, the UI auto-updates with workspace state. Other call sites (close, exit) do not retry.
    Reason: Main-thread callers get immediate circuit breaker error + fire-and-forget async recovery. The switcher had no way to learn when recovery completed, forcing the user to dismiss and reopen. Timer-based retry stays on main thread (ProjectManager thread-safety contract), uses the existing recovery mechanism, and adds no new infrastructure.
    Tradeoffs: Up to 10s of "Recovering" display if recovery is slow. If recovery never completes, user sees the original error after 5 attempts. Timer is canceled on dismiss/resetState to avoid stale callbacks.

- Decision 2026-02-17 ide-frame-retry: IDE frame read retries up to 10x before failing
    Decision: `positionWindows()` retries `getPrimaryWindowFrame()` up to 10 times at `windowPollInterval` (~100ms) when the AX title token isn't found. Retry is in ProjectManager (not AXWindowPositioner) to keep the positioner stateless.
    Reason: VS Code updates window titles asynchronously after launch. The AX API reads the title before VS Code applies the `AP:<projectId>` setting ~5.5% of the time. A brief retry brings this close to 0%.
    Tradeoffs: Up to ~1s additional delay in the worst case (title never appears), but normal case resolves in 1-2 retries (~200ms). Retry interval is injectable via `windowPollInterval` for fast tests.

- Decision 2026-02-17 hotkey-debounce: 300ms debounce on switcher hotkey
    Decision: `toggleSwitcher()` ignores rapid presses within 300ms of the last toggle. Debounce uses a simple timestamp comparison (not DispatchWorkItem).
    Reason: During AeroSpace outages, each hotkey press creates a new switcher session with its own workspace retry timer, causing a cascade of ~60 warnings in 3 seconds. Users naturally mash the hotkey when the switcher is slow to appear.
    Tradeoffs: Legitimate rapid toggle-toggle sequences are delayed by 300ms. This is imperceptible in practice since panel animation takes longer.

- Decision 2026-02-17 retry-session-guard: Workspace retry timer is session-scoped
    Decision: `scheduleWorkspaceStateRetry()` captures the session ID at creation time. Each timer tick compares it to the current session ID and self-cancels if they differ.
    Reason: With rapid hotkey presses, a dismissed session's timer could fire after a new session started, corrupting the new session's state.
    Tradeoffs: Negligible — one extra string comparison per tick.

- Decision 2026-02-16 ghrelease-arm64: Distribution shifts to GitHub tagged arm64 releases
    Decision: AgentPanel distribution is now signed + notarized arm64 artifacts published on GitHub tagged releases. Homebrew distribution is deferred to backlog work.
    Reason: This keeps release operations focused on a single packaging path needed now, while preserving deterministic installs/upgrades through versioned release assets.
    Tradeoffs: Intel macOS is unsupported. Users do not get package-manager install/upgrade ergonomics until Homebrew support is implemented.
