# Changelog

All notable changes to AgentPanel are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
