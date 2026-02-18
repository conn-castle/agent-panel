# Changelog

All notable changes to AgentPanel are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.3] - 2026-02-18

### Fixed

- **Doctor appears to hang with no feedback** -- Clicking "Run Doctor" dispatched Doctor.run() to a background thread but showed nothing until completion (20-30s when SSH hosts are unreachable). The Doctor window now opens immediately with "Running diagnostics..." loading text and disabled action buttons. The report populates when checks complete.
- **SSH check timeouts too slow** -- Doctor and settings block SSH commands used `ConnectTimeout=5` with 10s process timeout. Reduced to `ConnectTimeout=2` with 3s process timeout. Worst-case Doctor SSH checks drop from ~20s to ~6s. Adequate for LAN hosts; unreachable hosts fail faster.

## [0.1.2] - 2026-02-18

### Fixed

- **App freeze on startup** -- Every `ApSystemCommandRunner` instance spawned a login shell process during init to build an augmented PATH. With 9 instances created on the main thread during startup (`ProjectManager` launchers, `ApAeroSpace`, `WindowCycler`, etc.), this blocked the main thread for 5-10+ seconds, freezing the entire system. The augmented environment is now computed once (lazily, on first `run()` call) and cached globally via a thread-safe `static let`. Init is instant.
- **Menu bar freeze on click** -- `menuNeedsUpdate` called `captureCurrentFocus()` and `workspaceState()` synchronously on the main thread, each invoking AeroSpace CLI with a 5-second timeout. Now uses cached workspace state refreshed in the background after Doctor runs, switcher sessions end, and each menu open.
- **Switcher/Doctor/menu actions block main thread** -- `toggleSwitcher`, `openSwitcher`, `runDoctor`, and `addWindowToProject` all called AeroSpace CLI on the main thread. Moved all CLI calls to background dispatch queues with main-thread callbacks for UI updates.
- **Switcher panel blocks main thread** -- `refreshWorkspaceState()`, `closeProject()`, `captureCurrentFocus()`, `exitToNonProjectWindow()`, and workspace retry timer all called AeroSpace CLI synchronously on the main thread within the switcher panel. Dispatched all CLI calls to background queues; UI updates bounce back to main thread.
- **Command timeout stretches 5s to 10s** -- After a 5-second process timeout, the command runner still waited up to 4 additional seconds for pipe EOF signals that would never arrive. Now skips pipe EOF waits on timeout since the output is discarded anyway.
- **AeroSpace config reload blocks main thread** -- Moved the `aerospace.reloadConfig()` call during startup config update to a background thread to avoid blocking the main thread on the first command runner invocation.

## [0.1.1] - 2026-02-18

### Fixed

- **Doctor freeze in release build** -- `ExecutableResolver.runLoginShellCommand()` used synchronous `readDataToEndOfFile()` which blocks forever if the user's shell config (`.zshrc`/`.zprofile`) spawns background daemons that inherit the pipe's write-end file descriptor. Replaced with async `readabilityHandler` + EOF semaphore with bounded timeout, matching the safe pattern already used by `ApSystemCommandRunner`.

## [0.1.0] - 2026-02-17

Initial public release.

### Added

- **Project switching** -- global hotkey (`Cmd+Shift+Space`) opens a searchable switcher panel sorted by recency. Select a project to activate its workspace with VS Code and Chrome.
- **Workspace orchestration** -- each project gets a dedicated AeroSpace workspace (`ap-<projectId>`). Windows are created, moved, and focused automatically.
- **Chrome tab persistence** -- tabs are captured on project close and restored on activate. Per-project pinned tabs and default tabs configurable.
- **Window layout engine** -- configurable side-by-side positioning with screen-size-aware rules. Small screens maximize; wide screens tile. Requires Accessibility permission.
- **Window recovery** -- recover project windows to computed layout or center all windows across workspaces.
- **Window cycling** -- `Option+Tab` / `Option+Shift+Tab` cycles through windows in the current workspace (native implementation, includes floating windows).
- **SSH remote projects** -- VS Code Remote-SSH integration with remote `.vscode/settings.json` block management and parallel SSH Doctor checks.
- **Agent Layer integration** -- optional `al sync` + `al vscode` launch path for projects using the Agent Layer CLI.
- **VS Code color differentiation** -- per-project colors via the Peacock extension. Colors persist across settings.json re-injections.
- **Doctor diagnostics** -- comprehensive setup validation (Homebrew, AeroSpace, VS Code, Chrome, config, paths, SSH, permissions, hotkeys) with actionable fix guidance. Available in app UI and CLI (`ap doctor`).
- **AeroSpace auto-management** -- versioned config template with auto-update on startup. User keybindings and custom config preserved between updates.
- **AeroSpace resilience** -- circuit breaker (30s cooldown) prevents timeout cascades. Auto-recovery restarts crashed AeroSpace processes (max 2 attempts).
- **Focus stack** -- LIFO stack tracks non-project windows. `Shift+Enter` or `ap return` restores the last active non-project context.
- **Auto-start at login** -- configurable via `[app].autoStartAtLogin` or menu bar toggle. Uses `SMAppService`.
- **Auto-doctor on critical errors** -- background Doctor run when critical activation errors occur.
- **CLI (`ap`)** -- `doctor`, `show-config`, `list-projects`, `select-project`, `close-project`, `return` commands with ANSI color output and TTY detection.
- **Menu bar app** -- background-only (no Dock icon) with health indicator, config access, window recovery, and Doctor.
- **Signed and notarized releases** -- DMG (app), PKG (CLI installer), and tarball published via GitHub Releases. CI workflow handles signing, notarization, and stapling.
