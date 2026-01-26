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
