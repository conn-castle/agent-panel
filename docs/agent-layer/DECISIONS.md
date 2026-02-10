# Decisions

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
A rolling log of important, non-obvious decisions that materially affect future work (constraints, deferrals, irreversible tradeoffs). Only record decisions that future developers/agents would not learn just by reading the code.

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

- Decision 2026-01-11 9fd499c: Build workflow and Xcode project management
    Decision: Track `project.yml` and regenerate `AgentPanel.xcodeproj` via XcodeGen; keep a single repo-level `.xcodeproj` (no `.xcworkspace` in v1); drive build/test via `xcodebuild -project` scripts (`scripts/dev_bootstrap.sh`, `scripts/build.sh`, `scripts/test.sh`); commit the SwiftPM lockfile and resolve packages in CI; require Apple toolchain for developers/CI while keeping Xcode GUI optional.
    Reason: Deterministic, reviewable builds with minimal IDE friction and no brittle `.pbxproj` manual edits.
    Tradeoffs: Contributors must install `xcodegen`; additional script maintenance; occasional need to open Xcode for debugging/provisioning.

- Decision 2026-01-11 9fd499c: Logging contract
    Decision: Write JSON Lines log entries with UTC ISO-8601 timestamps to `agent-panel.log`; rotate at 10 MiB with up to 5 archives (`agent-panel.log.1`…`agent-panel.log.5`).
    Reason: Structured logs are easy to parse/filter; stable "tail this file" contract; prevents unbounded growth.
    Tradeoffs: Less human-readable without tooling; schema must stay stable; older history rotates out.

- Decision 2026-01-12 9fd499c: Minimum supported macOS version
    Decision: Set minimum supported macOS version to 15.7.
    Reason: Product requirement for initial release.
    Tradeoffs: Older macOS versions unsupported.

- Decision 2026-01-27 b1f4c2d: Homebrew required for AeroSpace install
    Decision: Require Homebrew and only support AeroSpace installation via Homebrew for now; manual installs are deferred.
    Reason: Deterministic, scriptable install path for onboarding and Doctor automation.
    Tradeoffs: Users without Homebrew cannot onboard until a manual install path is added.

- Decision 2026-02-03 brewonly: Homebrew-only AgentPanel install
    Decision: Support installing AgentPanel via Homebrew only; direct-download installs (zip/dmg) are not supported at this stage.
    Reason: Keep installs and upgrades deterministic and reduce release/distribution surface area while we reboot the project.
    Tradeoffs: Users without Homebrew cannot install AgentPanel; any future direct-download path will require intentional new work (signing/notarization + updater story).

- Decision 2026-02-03 guipath: GUI apps don't inherit shell PATH
    Decision: Use `ExecutableResolver` to find executables instead of `/usr/bin/env`. Searches standard paths first, falls back to login shell `which`.
    Reason: GUI apps launched via Finder/Dock get a minimal PATH without Homebrew or user additions. `/usr/bin/env` fails to find `code`, `brew`, `aerospace`, etc.
    Tradeoffs: Must maintain search path list; zsh fallback has performance cost.

- Decision 2026-02-03 pipes: Read pipes concurrently to avoid deadlock
    Decision: Use `readabilityHandler` to stream stdout/stderr while process runs, not after termination.
    Reason: Pipe buffers are ~64KB. If a process fills the buffer and blocks, waiting for termination before reading creates a deadlock.
    Tradeoffs: More complex thread synchronization.

- Decision 2026-02-04 e2ee3b6: SessionManager as single source of truth for state (SUPERSEDED)
    Decision: All state persistence (AppState, FocusHistory) and focus capture/restore flows through SessionManager in Core. App sets FocusOperationsProviding after config load.
    Reason: Consolidates state ownership in Core, eliminating duplicate state management in App/SwitcherPanelController. Enforces API boundaries via Swift access control.
    Tradeoffs: App must call setFocusOperations() after loading config; focus operations unavailable until then.
    **Superseded 2026-02-05:** SessionManager removed in favor of ProjectManager. FocusOperationsProviding protocol eliminated; ProjectManager uses AeroSpace directly for focus operations (CLI-based, no AppKit needed).

- Decision 2026-02-04 intentapi: Intent-based protocol pattern for cross-layer APIs
    Decision: Protocols crossing layer boundaries (Core↔App) use intent-based signatures like `captureCurrentFocus() -> CapturedFocus?` instead of implementation-specific types like `focusedWindow() -> ApWindow?`.
    Reason: Keeps implementation details (ApWindow, AeroSpace concepts) internal to the layer that owns them. Callers express what they want, not how to get it. Cleaner testability and looser coupling.
    Tradeoffs: Implementation must translate between internal types and intent-based types; slightly more code in the implementing layer.

- Decision 2026-02-04 appkitmod: Shared AgentPanelAppKit module (supersedes appkit)
    Decision: Create `AgentPanelAppKit` static framework containing `AppKitRunningApplicationChecker`. Both App and CLI depend on this shared module. Removes previous duplication in `AgentPanelApp/AppKitIntegration.swift` and `AgentPanelCLI/AppKitIntegration.swift`.
    Reason: Single source of truth for AppKit integration code; clean layering (Core → AppKit → App/CLI); no manual sync required.
    Tradeoffs: One additional build target; marginal complexity for small codebase, but scales if more AppKit integration is needed later.

- Decision 2026-02-05 pubaudit: Minimal public API surface in Core
    Decision: Make internal everything not directly used by App or CLI. Internal types include: `AgentPanel.appBundleIdentifier`, `ApCoreErrorCategory`, error factory functions, `ExecutableResolver`, `ApCommandResult`, `ApSystemCommandRunner`, `FileSystem`, `DefaultFileSystem`, `AppDiscovering`, `LaunchServicesAppDiscovery`, `HotkeyChecking`, `CarbonHotkeyChecker`, `DateProviding`, `SystemDateProvider`, `EnvironmentProviding`, `ProcessEnvironment`, `AeroSpaceInstallStatus`, `AeroSpaceCompatibility`, `AeroSpaceHealthChecking`, `IdNormalizer`, `ConfigLoadResult`, `ConfigLoader`, `ConfigError`, `ConfigErrorKind`, `LogEntry`, `DoctorMetadata`. Internal struct properties: `ApCoreError.category/detail/command/exitCode`, `ConfigFinding.detail/fix`, `DoctorFinding.title/bodyLines/snippet`. Internal static members: `ProjectColorPalette.named/sortedNames`, `DoctorActionAvailability.none`, `DoctorSeverity.sortOrder`, `DoctorReport.metadata`. Most `AeroSpaceConfigManager` and `DataPaths` methods/properties internal. All constructors internal where App/CLI never constructs directly. Dead code removed from SwitcherSession.
    Reason: Minimize public API surface; hide implementation details; cleaner module boundary; prevent accidental coupling to internal types.
    Tradeoffs: Tests must use `@testable import`; CORE_API.md must be kept in sync manually.

- Decision 2026-02-08 wsstate: Single-query workspace state in ProjectManager
    Decision: Replace split active/open workspace lookups with `ProjectManager.workspaceState()`, backed by one AeroSpace command: `list-workspaces --all --format "%{workspace}||%{workspace-is-focused}"`.
    Reason: Removes redundant CLI calls and guarantees active/open values are derived from one consistent snapshot instead of two separately timed queries.
    Tradeoffs: Depends on `workspace-is-focused` format support; parser contract must remain stable with AeroSpace output.

- Decision 2026-02-08 startbg: AeroSpace start must not run on main thread
    Decision: Enforce off-main-thread execution for `ApAeroSpace.start()` and run Doctor/startup AeroSpace actions on a background queue before updating UI.
    Reason: Startup readiness polling is synchronous and can block up to the configured timeout; keeping it off the main thread prevents UI stalls.
    Tradeoffs: Doctor/start actions become asynchronous from the app UI perspective and require callback-style UI updates.

- Decision 2026-02-08 chrometabs: Always-open tabs instead of Chrome pinned tabs
    Decision: Use "always-open" tabs (opened as regular tabs, leftmost position) instead of Chrome pinned tabs. Chrome does not expose a programmatic API to pin tabs; AppleScript and remote debugging can only create regular tabs.
    Reason: Chrome tab pinning is only available via user interaction (right-click → Pin). No scriptable interface exists.
    Tradeoffs: Tabs appear as regular tabs, not pinned; users must manually pin if desired. Always-open tabs are re-created on every fresh activation, which is functionally equivalent for the use case.

- Decision 2026-02-08 freshonly: Tab restore only on fresh Chrome window creation
    Decision: Tab restore runs only when `selectProject` freshly launches a new Chrome window (tracked via `FindOrLaunchOutcome.wasLaunched`). If Chrome is already open for the project, all tab operations are skipped.
    Reason: Restoring tabs into an existing Chrome window would disrupt user's current tab state. The intent is to reconstruct the tab set only when starting from scratch.
    Tradeoffs: If the user manually closes all tabs in an existing Chrome window, reactivating the project won't restore them (user must close and reactivate the project).

- Decision 2026-02-09 focusstack: LIFO FocusStack replaces single-slot capturedProjectExitFocus
    Decision: Replace single `CapturedFocus?` slot with a LIFO `FocusStack` of non-project window entries. Add `workspace` field to `CapturedFocus`. Filter on push: only non-project windows (workspace not prefixed with `ap-`) are recorded. Pop discards stale (destroyed) windows automatically. No rollback on activation failure.
    Reason: Single-slot design lost the return-to window after close→reopen→close cycles. Stack enables "exit project space" semantic: Z (main) → A (ap-alpha) → B (ap-beta) → exit returns to Z, not A.
    Tradeoffs: Focus stack is not persisted (window IDs don't survive restarts); test-only `pushFocusForTest` helper added for injection.

- Decision 2026-02-09 allauncher: Agent Layer launcher uses `al sync` + direct `code` (two-step)
    Decision: Both `ApVSCodeLauncher` and `ApAgentLayerVSCodeLauncher` create `.code-workspace` files via `ApIdeToken.createWorkspaceFile()`. AL launcher runs two steps: (1) `al sync` with CWD = project path (regenerates agent layer config from `.agent-layer/`), (2) `code --new-window <workspace>` (opens one VS Code window with AP tag). `ProjectManager.selectProject` chooses launcher via `project.useAgentLayer`.
    Reason: `al vscode` unconditionally appends `.` (CWD) to the args it passes to `code` (`internal/clients/vscode/launch.go`), causing two VS Code windows. Splitting into `al sync` + direct `code` avoids the duplicate window. Token-based window identification (`AP:<id>` in workspace title) is uniform across all project types.
    Tradeoffs: Loses `CODEX_HOME` env var that `al vscode` normally sets (only needed by Codex VS Code extension). SSH + AL is mutually exclusive (rejected at config parse time). Once `al vscode` is fixed upstream, can revert to single-command launch.

- Decision 2026-02-09 cmdrunnerwd: CommandRunning protocol extended with workingDirectory
    Decision: Add `workingDirectory: String?` as 4th parameter to `CommandRunning.run()`. Provide two convenience extensions (2-param and 3-param) that forward `workingDirectory: nil` to preserve all existing call sites.
    Reason: AL launcher needs to set process working directory. Convenience extensions prevent breaking ~23 production and ~6 test call sites.
    Tradeoffs: All mock `CommandRunning` implementations must implement the 4-param method; convenience extensions may mask unintended nil working directory.

- Decision 2026-02-09 pathprop: Propagate augmented PATH to child processes
    Decision: `ApSystemCommandRunner` builds an augmented environment at init by merging standard search paths, the user's login shell PATH (via `$SHELL -l -c 'echo $PATH'`), and the current process PATH (deduplicated, order preserved). Every child process receives this environment via `process.environment`. Login shell command has a 5-second semaphore timeout. `$SHELL` is validated as an absolute path (falls back to `/bin/zsh`). Pipe EOF wait uses a fixed 2-second timeout to avoid doubling the caller's timeout.
    Reason: GUI apps inherit a minimal PATH. Child processes (e.g., `al vscode` calling `code`) also inherited this minimal PATH and failed. Uses `$SHELL` to support bash users. Bounded timeout prevents hangs from slow shell init files.
    Tradeoffs: One login shell spawn per `ApSystemCommandRunner` construction (~50ms); cached as `let` property. Non-POSIX shells (fish) may return nil PATH (safe fallback).

- Decision 2026-02-09 wsfallback: Workspace fallback when focus stack is exhausted
    Decision: When `closeProject` or `exitToNonProjectWindow` exhausts the focus stack, fall back to focusing the first non-project workspace (workspace name not prefixed with `ap-`). Switcher dismiss adds a workspace-level fallback (`focusWorkspace(name: focus.workspace)`) between window focus failure and app activation.
    Reason: Users were stranded with no focus change when closing a project without a prior non-project window. Workspace-level focus is a sensible "closest available" fallback.
    Tradeoffs: Fallback may land the user on an arbitrary non-project workspace if multiple exist; this is better than no focus change.

- Decision 2026-02-09 closefocus: Refresh captured focus after close-project in switcher
    Decision: After `closeProject` succeeds in the switcher's `performCloseProject`, refresh `capturedFocus` by re-capturing current focus (post-close restoration) and update `previouslyActiveApp` to the frontmost application. If focus capture yields AgentPanel (or bundle ID is unavailable), clear both so dismiss does not attempt a stale restore.
    Reason: `closeProject` already handles focus restoration (via focus stack or workspace fallback). The switcher's dismiss path could overwrite that with stale pre-switcher focus (including a just-destroyed project workspace). The switcher also stays open after close, so subsequent project selection must use the new non-project focus baseline.
    Tradeoffs: If focus capture cannot determine a non-AgentPanel window, focus restoration on dismiss is disabled (safe default), and the user may need to reopen the switcher to recapture focus before activating a project.

- Decision 2026-02-08 snaptruth: Snapshot-is-truth for Chrome tab persistence (supersedes filtering approach)
    Decision: Save ALL captured Chrome tab URLs verbatim on close (no filtering of pinned/always-open tabs). On activation with an existing snapshot, restore snapshot URLs directly. Always-open + default tabs are only used for cold start (no snapshot). Stale snapshots are deleted only when capture returns empty (Chrome window confirmed gone); capture failures preserve the existing snapshot. Chrome launches with real tabs in a single AppleScript (no example.com placeholder). URL resolution is deferred until after confirming Chrome needs a fresh launch. If tab-restore launch fails, Chrome falls back to launching without tabs.
    Reason: Exact-match URL filtering is unreliable because Chrome redirects URLs (e.g., `todoist.com/` → `todoist.com/app/today`), git remote URLs differ from web URLs, and other dynamic URL changes. Single-phase launch eliminates visible flashing.
    Tradeoffs: Snapshot may contain URLs that overlap with always-open config; this is harmless since the snapshot IS the intended tab state. Cold-start defaults may differ from what the user eventually navigates to.
