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

- Decision 2026-02-23 focushistory: Persist non-project focus history for cross-process restore
    Decision: Persist focus stack + most recent non-project focus in `~/.local/state/agent-panel/state.json` via `FocusHistoryStore`, with versioned schema, 7-day prune, and serialized persistence queue.
    Reason: Exit/close focus restoration was unreliable across app/CLI sessions and restarts; persisted history is the single source of truth for restoring the last non-project window.
    Tradeoffs: Adds disk writes on focus updates; future state extensions must be versioned to avoid breaking older reads.

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

- Decision 2026-02-12 axprompt: Accessibility prompt via Doctor button only (not app launch, superseded by `axstartupbuild`)
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
    Reason: Main-thread callers get immediate circuit breaker error + fire-and-forget async recovery. The switcher had no way to learn when recovery completed, forcing the user to dismiss and reopen. Timer-based retry stays on main thread to keep UI updates predictable, uses the existing recovery mechanism, and adds no new infrastructure.
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

- Decision 2026-02-17 releaseci: Single-job release workflow with script-based signing and packaging (historical; superseded by `ci26baseline` / `xcode26canonical`)
    Decision: At the time, release workflow used a single CI job on `macos-15` with 5 scripts (`ci_setup_signing`, `ci_archive`, `ci_package`, `ci_notarize`, `ci_release_validate`) + `ci_preflight` (runs in CI on every push). Entitlements file committed at `release/AgentPanel.entitlements`. Release config signing settings in `project.yml` (Manual style, Developer ID Application identity, hardened runtime) — Debug builds remain unsigned. Current baseline is tracked in `ci26baseline` and `xcode26canonical`.
    Reason: Single job avoids artifact transfer overhead between jobs. Scripts follow existing `scripts/` convention and are locally testable.
    Tradeoffs: Long single job (~15-20 min) vs parallel jobs. CLI tarball is not notarized (tarballs cannot be stapled; users must clear quarantine manually).

- Decision 2026-02-18 cached-env: ApSystemCommandRunner caches augmented environment globally
    Decision: Replaced per-instance `augmentedEnvironment` with a `static let cachedEnvironment` on `ApSystemCommandRunner`. The environment is computed lazily on first `run()` call (not during `init()`). All instances share the cached value. `buildAugmentedEnvironment(resolver:)` remains a static method for direct test use.
    Reason: Nine `ApSystemCommandRunner` instances are created on the main thread during app startup (via `ProjectManager`, `ApAeroSpace`, `WindowCycler`, etc.). Each previously spawned a login shell process (up to 7s blocking per instance), freezing the system for 5-10+ seconds total. The login shell PATH doesn't change during app lifetime, so computing it once eliminates all redundant work.
    Tradeoffs: All instances share the same environment (no per-instance customization). In practice, all production instances used the default `ExecutableResolver()`, so this is a no-op change. Tests call `buildAugmentedEnvironment` directly with custom resolvers, bypassing the cache.

- Decision 2026-02-18 menu-cache: Menu uses cached workspace state instead of live AeroSpace CLI calls
    Decision: `menuNeedsUpdate` reads from `cachedWorkspaceState` and `menuFocusCapture` properties instead of calling `captureCurrentFocus()` and `workspaceState()` live. A background `refreshMenuStateInBackground()` updates the cache after Doctor refreshes, switcher session ends, and each menu open. `toggleSwitcher`, `openSwitcher`, `runDoctor`, and `addWindowToProject` also dispatch AeroSpace CLI calls to background queues.
    Reason: `NSMenuDelegate.menuNeedsUpdate()` runs synchronously on the main thread. AeroSpace CLI calls have 5-second timeouts. If AeroSpace is slow or unresponsive, the menu and app freeze completely. The circuit breaker only helps after the first timeout trips it — the first menu open always blocks.
    Tradeoffs: Menu shows slightly stale data (from last background refresh) instead of live state. In practice, the cache is refreshed frequently enough (every Doctor run, every switcher session, every menu open) that staleness is minimal.

- Decision 2026-02-18 timeout-eof-skip: Skip pipe EOF waits after command timeout
    Decision: When `ApSystemCommandRunner.run()` times out and terminates the process, skip the 2s+2s pipe EOF semaphore waits and immediately clean up handlers. EOF waits are only performed on normal (non-timeout) process exit.
    Reason: After a 5s AeroSpace CLI timeout, the additional 4s of EOF waiting stretched total latency to ~9-10s. Since the output is discarded on timeout anyway, there's no reason to wait for it. This halved worst-case latency for timeout paths.
    Tradeoffs: None meaningful — timed-out output was always discarded. Edge case: if a process writes valid output after being terminated but before pipes close, that data is now lost. This is acceptable because we never use output from timed-out commands.

- Decision 2026-02-18 doctor-loading: Show Doctor window immediately with loading state
    Decision: `runDoctor()` and `runDoctorAction()` now call `showLoading()` on the Doctor window immediately (on main thread) before dispatching `Doctor.run()` to a background thread. The window shows "Running diagnostics..." with disabled action buttons until the report arrives.
    Reason: `Doctor.run()` can take 6-30+ seconds (SSH timeouts when hosts are unreachable). With no visual feedback, users perceive the app as hung. The loading state provides instant acknowledgement.
    Tradeoffs: Window appears before the report is ready, showing a brief loading message. Close button remains enabled so users can dismiss during loading.

- Decision 2026-02-18 ssh-timeout-reduction: Reduce SSH timeouts from 10s to 3s
    Decision: All SSH commands (Doctor checks + settings block read/write) now use `ConnectTimeout=2` and `timeoutSeconds: 3`, down from `ConnectTimeout=5` / `timeoutSeconds: 10`.
    Reason: SSH targets are LAN hosts (e.g., `happy-mac`). Local connections complete in milliseconds; if a host doesn't respond in 2 seconds, it's unreachable. Doctor SSH checks are WARN-level diagnostics — speed of feedback is more important than tolerating slow networks.
    Tradeoffs: Remote SSH hosts (WAN, high latency) may false-fail if connection takes >2s. If users need longer timeouts for remote hosts, this would need to become configurable. Current use case is exclusively LAN.

- Decision 2026-02-18 cli-build-version: CLI version embedded via buildVersion constant
    Decision: `AgentPanel.version` falls back to a `buildVersion` string constant in `Identity.swift` when `Bundle.main.infoDictionary` is nil (CLI tool context). CI preflight verifies `buildVersion` matches `MARKETING_VERSION` in `project.yml`.
    Reason: CLI tools (`type: tool` in XcodeGen) have no Info.plist bundle. `Bundle.main.infoDictionary` returns nil, causing the version to fall back to `"0.0.0-dev"`. The constant provides correct version reporting without build scripts or generated files.
    Tradeoffs: Requires updating two locations when bumping the version (project.yml + Identity.swift). CI preflight catches mismatches automatically.

- Decision 2026-02-18 accessibility-warn: Accessibility check is WARN, not FAIL
    Decision: Doctor reports missing Accessibility permission as WARN instead of FAIL. Menu bar icon shows orange (not red) when Accessibility is the only issue.
    Reason: macOS revokes Accessibility permission when the app binary changes (e.g., after every update). This caused the menu bar to show red on every version update, alarming users into thinking the app was broken. Without Accessibility, the app still functions (project switching, Chrome tabs, etc.) — only window positioning is degraded.
    Tradeoffs: Users may not notice the missing Accessibility as urgently with orange vs red. The "Request Accessibility" Doctor button remains available.

- Decision 2026-02-18 doctor-log-findings: Doctor log entries include finding titles for remote diagnostics
    Decision: `logDoctorSummary` now includes `fail_findings` and `warn_findings` context keys with semicolon-separated finding titles.
    Reason: Previous logs only showed counts (e.g., `fail_count: 1`) without identifying WHAT failed. This made remote debugging impossible — multiple iterations were spent investigating Doctor hanging when the actual issue was an Accessibility permission FAIL that the logs didn't reveal.
    Tradeoffs: Log entries are slightly larger. Finding titles are truncated-safe since they're short strings.

- Decision 2026-02-18 doctor-comprehensive-logging: Doctor logs include full rendered report, timing, and binary path
    Decision: Every Doctor log entry (`doctor.refresh.completed`, `doctor.run.completed`) now includes: full rendered report text (`rendered_report`), total duration (`duration_ms`), per-section timing breakdown (`timing_*_ms`), and finding titles. Startup log includes `binary_path`, `bundle_path`, and `macos_version`. Doctor report header shows duration and section timings.
    Reason: Four release iterations (v0.1.0–v0.1.3) were spent investigating remote issues without sufficient log data. The user explicitly requested "everything you need to know for sure what is wrong" in a single release attempt.
    Tradeoffs: Log entries are significantly larger (~2-4KB per Doctor run). Acceptable for a diagnostic tool that runs infrequently.

- Decision 2026-02-20 capture-on-switch: Capture window positions during project-to-project switching
    Decision: `selectProject()` now calls `captureWindowPositions(sourceProjectId)` at the start when `preCapturedFocus.workspace` starts with `"ap-"`. Source project ID is extracted from the workspace name using the existing `projectId(fromWorkspace:)` helper. `SavedWindowFrames.chrome` is now optional (`SavedFrame?`) — Chrome frame read failure saves IDE-only (partial save) instead of aborting. Partial-save and partial-restore paths log at ERROR level to ensure visibility.
    Reason: `captureWindowPositions()` was only called from `closeProject()` and `exitToNonProjectWindow()`, never during the most common workflow (project-to-project switching via the switcher). This meant window positions were never persisted during normal use, causing every return to a project to use computed layout instead of the user's manual arrangement.
    Tradeoffs: One extra `captureWindowPositions()` call per project switch (non-fatal, ~10ms). The optional Chrome frame is a bandaid for edge cases where Chrome is absent — partial saves log at ERROR so the underlying cause can be investigated.

- Decision 2026-02-17 direct-codesign: Use direct `codesign` instead of `xcodebuild -exportArchive`
    Decision: `ci_archive.sh` extracts the .app from the xcarchive and re-signs with `codesign --force --deep --options runtime --timestamp --entitlements` instead of using `xcodebuild -exportArchive` with ExportOptions.plist.
    Reason: `IDEDistribution` (used by `-exportArchive`) fails on GitHub Actions CI runners with "Unknown Distribution Error" / empty valid distribution methods set. Root cause: incomplete Apple intermediate certificate chain in the CI runner environment that `IDEDistribution` cannot resolve. Direct `codesign` bypasses `IDEDistribution` entirely.
    Tradeoffs: Loses automatic Swift stdlib stripping and architecture thinning that `-exportArchive` provides. Acceptable for Developer ID distribution (not App Store).

- Decision 2026-02-20 fuzzysearch: Fuzzy matcher with tiered scoring replaces exact match types
    Decision: `FuzzyMatcher.score(query:target:)` replaces the old `matchType()` in `ProjectManager.sortedProjects()`. Scores both `project.name` and `project.id`, uses `max(nameScore, idScore)`. Tiers: prefix (1000) > word-boundary acronym (800) > substring (600) > fuzzy (gap-penalized, 1-500) > no match (0). Sort by score descending, then recency, then config order.
    Reason: Old matching was exact substring only — "al" could not match "Agent Layer". Fuzzy matching with word-boundary acronym detection handles abbreviations, acronyms, and partial queries. Dual-field scoring (name + ID) preserves existing ID-based query behavior.
    Tradeoffs: Fuzzy tier can surface low-relevance matches for very short queries (single char matches many projects). Mitigated by gap penalties and position bonuses. Score values are tunable without interface changes.

- Decision 2026-02-20 doctorui: Doctor window UI revamp — attributed string renderer + loading spinner + button hierarchy
    Decision: New `DoctorReportRenderer` (App layer) produces `NSAttributedString` with colored severity labels. Loading state uses `NSProgressIndicator` spinner. Conditional action buttons are hidden (not disabled) when unavailable. Appearance changes re-render via KVO on `NSWindow.effectiveAppearance`. Made `DoctorFinding.bodyLines`, `.snippet`, `.snippetLanguage` and `DoctorSeverity.sortOrder` public.
    Reason: Plain text dump was unreadable for users; no visual severity distinction, no loading feedback, 7 identical buttons created clutter. Attributed string approach mirrors Core's `rendered()` structure but adds color/typography hierarchy.
    Tradeoffs: Making Core properties public slightly widens the API surface. KVO observation approach (vs delegate method) requires retaining the observation token. Conditional button hiding means the button bar width varies — acceptable for a resizable window.

- Decision 2026-02-21 switcher-perf-hybrid: Switcher warm-open/filter path uses cache + planner updates
    Decision: `SwitcherPanelController` now reuses a cached config snapshot when config fingerprint (`mtime + size`) is unchanged, debounces keystroke filtering by 30ms, and applies planner-selected table updates (`fullReload` / `visibleRowsReload` / `noReload`) with targeted selection repaint.
    Reason: The previous switcher path reloaded config on every open and refreshed table/selection aggressively on each keystroke, adding avoidable work in the hottest interactions.
    Tradeoffs: Fingerprint metadata can miss rare same-size/same-mtime edits; the implementation stays conservative by forcing reload when fingerprint is missing and falling back to full reload on structural row changes.

- Decision 2026-02-21 optiontab-overlay: Option-Tab overlay lifecycle uses Carbon hotkeys plus release watchdog fallback
    Decision: `FocusCycleHotkeyManager` listens to both `kEventHotKeyPressed` and `kEventRawKeyModifiersChanged`; overlay sessions start on first Option-Tab, advance on repeated presses, and commit on Option release. A polling watchdog (`CGEventSource.flagsState(.combinedSessionState)`) runs while overlay is active so release-to-commit still occurs if modifier-change events are missed. Option-state checks include both left and right Option keys. For 0-1 windows or when switcher is visible, behavior falls back to immediate `cycleFocus`.
    Reason: `RegisterEventHotKey` alone cannot detect Option release, and modifier-change delivery is not fully reliable in all focus states. The watchdog preserves deterministic release-to-commit UX without introducing an event tap subsystem.
    Tradeoffs: App-layer overlay behavior remains primarily manual-test coverage because there is no app XCTest target. Polling adds a small periodic check while the overlay is active and requires careful lifecycle cleanup to avoid stale timers.

- Decision 2026-02-21 doctor-release-parity: Doctor rendering uses explicit palette and release workflow enforces Xcode 17+ (superseded by `ci26baseline` / `xcode26canonical`)
    Decision: Doctor rich-text rendering moved to AgentPanelAppKit with explicit RGB palettes (light/dark) and report-background coordination, and release CI now fails when the selected Xcode major version is below 17.
    Reason: Signed release artifacts built with older toolchains showed Doctor reports as visually blank while logs and copy actions proved report generation was correct; explicit palette/background pairing removes dynamic-color ambiguity, and the Xcode guard prevents shipping on the known-bad toolchain path.
    Tradeoffs: Release workflow may block until CI runners provide Xcode 17+; Doctor colors are now app-defined tokens instead of dynamic system semantic colors.

- Decision 2026-02-21 ci26baseline: CI/release baseline moves to macos-26 + Xcode 26+
    Decision: Build/test and release workflows now run on `macos-26`, keep Xcode selection on `latest-stable`, and enforce `XCODE_MAJOR >= 26`. CI action majors updated to `actions/checkout@v6` and `actions/cache@v5`.
    Reason: Multiple release-only UI regressions were caused by CI/local toolchain mismatch. Moving both CI lanes to a current baseline removes the legacy Xcode 16 path and keeps parity with modern local builds.
    Tradeoffs: `macos-26` is a public-preview image today, so queueing/runner-image instability risk is higher than GA images until GitHub promotes it.

- Decision 2026-02-21 axstartupbuild: Accessibility prompt runs on startup once per build (supersedes `axprompt`)
    Decision: If Accessibility is not trusted, AgentPanel requests permission once per installed build (`CFBundleVersion`) during startup. The Doctor "Request Accessibility" action remains available as a manual retry path.
    Reason: Startup prompting gives a better first-run UX for window layout features and reduces the chance users stay in a degraded state because they never open Doctor.
    Tradeoffs: First launch of a new build can show a modal system prompt; users who dismiss still need Doctor or System Settings for a later retry.

- Decision 2026-02-21 xcode26canonical: Xcode 26+ is the canonical baseline (supersedes older 17+ wording)
    Decision: Treat `ci26baseline` as the authoritative release/CI toolchain floor (`Xcode 26+`); references to `Xcode 17+` in older entries are historical context only.
    Reason: A single explicit baseline avoids contradictory operator guidance across workflows, release docs, and memory files.
    Tradeoffs: Historical entries remain for auditability, so readers must treat superseded wording as non-authoritative.

- Decision 2026-02-23 workspacerouting: Canonical WorkspaceRouting utility owns workspace naming and non-project destination strategy
    Decision: `WorkspaceRouting` enum in Core owns the `"ap-"` project prefix, project-ID extraction, and a `preferredNonProjectWorkspace(from:hasWindows:)` strategy that prefers a non-project workspace with windows, then any non-project workspace, then `"1"` as fallback. `ProjectManager` and `WindowRecoveryManager` delegate to it instead of defining their own constants and logic.
    Reason: Workspace prefix was duplicated across two modules; move/recovery flows hardcoded workspace `"1"` while other flows used dynamic discovery, creating inconsistent behavior.
    Tradeoffs: `moveWindowFromProject` now makes additional AeroSpace CLI calls (workspace listing + per-workspace window listing) to discover the destination. In practice this is 1-3 extra calls for typical setups.

- Decision 2026-02-24 focus-restore-bounds: Focus restore retries are bounded and single-attempt per invocation
    Decision: `ProjectManager` now uses one optional-lookup restore flow for stack/recent candidates, skips retrying the same window twice within one exit/close invocation, and bounds retry-preserved entries per window (max 2 attempts, max preserved-retry age 10 minutes). `moveWindowFromProject` fast-path destination selection is also validated with a per-workspace listing before use.
    Reason: The prior implementation duplicated restore logic across lookup/non-lookup paths, could double-block one invocation by retrying the same candidate via the recent path, and allowed unbounded preserve/retry loops for stale candidates.
    Tradeoffs: Persisted focus candidates that exceed retry/age bounds are invalidated earlier, so restoration may fall back to workspace routing more often in prolonged unstable-focus scenarios.

- Decision 2026-02-24 focus-stable-recheck: Focus stabilization re-checks immediately after re-assert
    Decision: `focusWindowStable` and `focusWindowStableSync` now re-check `focusedWindow` immediately after each `focusWindow` re-assert and clamp sleep intervals to remaining timeout budget.
    Reason: Short timeout windows in CI could expire between re-assert and the next poll iteration, causing false `noPreviousWindow` failures even when focus had already stabilized.
    Tradeoffs: Adds one extra `focusedWindow` call per poll loop iteration and slightly more branching in focus loops, but removes timeout-boundary flakiness and keeps behavior deterministic.

- Decision 2026-02-28 dev-app-identity: Dev app uses distinct bundle identity while sharing config/state paths
    Decision: Add a separate `AgentPanelDev` app target/scheme with `PRODUCT_BUNDLE_IDENTIFIER=com.agentpanel.AgentPanel.dev` and `PRODUCT_NAME=AgentPanel Dev`, while keeping existing `AgentPanel` release identity unchanged and continuing to use shared `~/.config/agent-panel` and `~/.local/state/agent-panel` paths.
    Reason: macOS Accessibility/Automation permissions are keyed by app identity, so dev and release need distinct bundle IDs for side-by-side installation without collisions; config/state should remain single-source-of-truth across both variants.
    Tradeoffs: Dev and release share persisted state/logs and can influence each other’s history; login-item and UserDefaults behavior is identity-scoped and may differ between variants by design.

- Decision 2026-02-28 recover-all-routing: Recover-all routes project-tagged windows before workspace recovery
    Decision: `WindowRecoveryManager.recoverAllWindows` now scans every window, moves `AP:<projectId>` VS Code/Chrome windows for known configured projects into `ap-<projectId>` when misplaced, then runs workspace recovery for each affected workspace (layout-aware for project workspaces, generic for non-project workspaces).
    Reason: Global recovery previously forced all windows into one non-project workspace, which broke project workspace layout semantics and failed to repair misplaced project windows back to canonical project destinations.
    Tradeoffs: Recovery now depends on title-token correctness for project routing and performs additional workspace-level recovery passes, which increases command count relative to the old one-destination flow.
