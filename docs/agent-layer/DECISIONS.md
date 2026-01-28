# Decisions

Note: This is an agent-layer memory file. It is primarily for agent use.

## Decision Log

<!-- ENTRIES START -->

- Decision 2026-01-11 9fd499c: Build workflow and Xcode project management
    Decision: Track `project.yml` and regenerate `ProjectWorkspaces.xcodeproj` via XcodeGen; keep a single repo-level `.xcodeproj` (no `.xcworkspace` in v1); drive build/test via `xcodebuild -project` scripts (`scripts/dev_bootstrap.sh`, `scripts/build.sh`, `scripts/test.sh`); commit the SwiftPM lockfile and resolve packages in CI; require Apple toolchain for developers/CI while keeping Xcode GUI optional.
    Reason: Deterministic, reviewable builds with minimal IDE friction and no brittle `.pbxproj` manual edits.
    Tradeoffs: Contributors must install `xcodegen`; additional script maintenance; occasional need to open Xcode for debugging/provisioning.

- Decision 2026-01-11 9fd499c: Core target is a static framework
    Decision: Build `ProjectWorkspacesCore` as a static framework so `pwctl` can link it without requiring embedded runtime frameworks.
    Reason: A command-line tool does not embed dependent dynamic frameworks by default, which causes runtime loader failures during development.
    Tradeoffs: Static linking can increase binary size; switching to dynamic later would require explicit embedding and runtime search path configuration.

- Decision 2026-01-11 9fd499c: Dependencies and hotkey policy
    Decision: Allow third-party Swift dependencies only for TOML parsing (`TOMLDecoder` pinned to 0.4.3 via SwiftPM); hotkey is fixed to ⌘⇧Space and not configurable; implement hotkey via Carbon `RegisterEventHotKey` with no third-party hotkey libraries.
    Reason: Minimize runtime dependencies while keeping parsing reliable and hotkey implementation stable.
    Tradeoffs: TOML dependency must be maintained; more custom code in-house for hotkey.

- Decision 2026-01-11 9fd499c: Logging contract
    Decision: Write JSON Lines log entries with UTC ISO-8601 timestamps to `workspaces.log`; rotate at 10 MiB with up to 5 archives (`workspaces.log.1`…`workspaces.log.5`).
    Reason: Structured logs are easy to parse/filter; stable "tail this file" contract; prevents unbounded growth.
    Tradeoffs: Less human-readable without tooling; schema must stay stable; older history rotates out.

- Decision 2026-01-11 9fd499c: Config defaults and doctor severity
    Decision: Apply deterministic defaults for non-structural config omissions; Doctor FAIL only for structural/safety-critical issues and otherwise emit WARN/OK; config parsing tolerates unknown keys so unsupported keys can be WARNed.
    Reason: Keep the tool easy to configure and robust on a fresh machine without silent behavior.
    Tradeoffs: More defaulting behavior to document and test; warnings may be noisy.

- Decision 2026-01-11 9fd499c: Reserved fallback workspace pw-inbox
    Decision: Hard-code `pw-inbox` as the fallback workspace; forbid `project.id == "inbox"`; Doctor performs connectivity check by switching to `pw-inbox` once.
    Reason: Make Close(Project) deterministic and ensure there is always a safe workspace to land on.
    Tradeoffs: Users cannot use `inbox` as a project id.

- Decision 2026-01-11 9fd499c: CI test scope and opt-in integration tests
    Decision: Require unit tests in CI; gate real AeroSpace integration tests behind `RUN_AEROSPACE_IT=1` for local runs only.
    Reason: Real window manipulation and permissions are not reliably runnable in CI environments.
    Tradeoffs: Less end-to-end coverage in CI; engineers must run opt-in integration tests locally.

- Decision 2026-01-11 9fd499c: Distribution channels
    Decision: Ship both a Homebrew cask (recommended) and a signed+notarized direct download artifact from a single canonical pipeline.
    Reason: Provide a smooth install/update path with a fallback for machines without Homebrew.
    Tradeoffs: More packaging complexity; release process must keep artifacts in sync.

- Decision 2026-01-12 9fd499c: Minimum supported macOS version
    Decision: Set minimum supported macOS version to 15.7.
    Reason: Product requirement for initial release.
    Tradeoffs: Older macOS versions unsupported.

- Decision 2026-01-14 02e7dee: Skip hotkey check when agent runs
    Decision: Keep both `pwctl doctor` and in-app "Run Doctor"; skip hotkey registration check when the agent app is already running.
    Reason: Prevents false FAIL results during normal use when the agent already holds the hotkey.
    Tradeoffs: Hotkey check relies on agent detection.

- Decision 2026-01-25 f311f35: AeroSpace onboarding safe config
    Decision: Install a ProjectWorkspaces-safe AeroSpace config at `~/.aerospace.toml` only when no config exists; never modify existing configs; Doctor handles config state checks, safe installs, and emergency `aerospace enable off` action.
    Reason: Prevent tiling shock while preserving existing AeroSpace setups.
    Tradeoffs: Users with existing configs must opt into changes themselves.

- Decision 2026-01-26 24a9013: Extract Doctor checker structs
    Decision: Extract focused checker structs from Doctor.swift: PermissionsChecker (accessibility, hotkey), AppDiscoveryChecker (Chrome, IDEs), AeroSpaceChecker (all AeroSpace functionality). Doctor orchestrates checkers via composition.
    Reason: Doctor.swift grew to ~1165 lines with mixed responsibilities; extraction improves maintainability before Phase 3 adds more checks.
    Tradeoffs: More files to navigate; slight indirection in code flow.

- Decision 2026-01-26 c1a9e7f: Chrome launcher precondition and detection policy
    Decision: Require the expected AeroSpace workspace to be focused before creating Chrome, and use fixed polling constants with Chrome-only ID diffing plus explicit error outcomes.
    Reason: Keeps activation responsible for workspace switching and avoids flaky, non-deterministic window detection.
    Tradeoffs: Callers must ensure focus before launching; more error handling in activation code.

- Decision 2026-01-27 a6d2f1b: Activation ignores windows outside the workspace
    Decision: Activation only considers windows already in `pw-<projectId>` and never moves or adopts windows from other workspaces; missing windows are created in the focused workspace.
    Reason: Prevents hijacking user windows and keeps activation deterministic.
    Tradeoffs: If AeroSpace rules move new windows elsewhere, activation fails and requires user configuration fixes.

- Decision 2026-01-27 e7c3a1b: Workspace-only window enumeration
    Decision: Never scan or use windows outside `pw-<projectId>` (no `list-windows --all` in activation or Chrome detection); only enumerate the focused project workspace.
    Reason: Eliminates any chance of hijacking user windows and keeps behavior predictable.
    Tradeoffs: Less recovery when windows spawn outside the workspace; errors surface as timeouts and require user configuration fixes.

- Decision 2026-01-27 b1f4c2d: Homebrew required for AeroSpace install
    Decision: Require Homebrew and only support AeroSpace installation via Homebrew for now; manual installs are deferred.
    Reason: Deterministic, scriptable install path for onboarding and Doctor automation.
    Tradeoffs: Users without Homebrew cannot onboard until a manual install path is added.

- Decision 2026-01-28 c3f1a9: Token-based window identification
    Decision: Identify Chrome and VS Code windows by deterministic token (`PW:<projectId>`) in window titles; allow `list-windows --all` only for token matching and move matched windows into the project workspace; fail on zero or multiple matches.
    Reason: Deterministic, no-guessing identification without hijacking unrelated windows; recovers when windows spawn outside the workspace.
    Tradeoffs: Window titles include a visible token; multiple tokened windows must be resolved manually.

- Decision 2026-01-28 c3f1aa: VS Code workspace files in state dir
    Decision: Store generated `.code-workspace` files under `~/.local/state/project-workspaces/vscode` and set `window.title` with the deterministic token.
    Reason: Keeps generated artifacts in state cache and enables deterministic VS Code window identification.
    Tradeoffs: Workspace files move from config to state; VS Code titles include a visible token.

- Decision 2026-01-28 8e2d6bf: Chrome launch uses open -na with optional profile directories
    Decision: Launch Chrome via `open -na` with `--window-name=PW:<projectId>` so window titles are deterministic; support optional per-project `chromeProfileDirectory` and surface available profile directory names in Doctor.
    Reason: Chrome ignores `--new-window/--window-name` when launched without `-n` on some machines; profile selection is required for deterministic behavior when multiple profiles are open.
    Tradeoffs: `-n` starts a new Chrome instance; profile configuration requires users to know Chrome profile directory names.
