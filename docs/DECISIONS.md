# Decisions

Purpose: Rolling log of important decisions (brief).

Notes for updates:
- Add an entry when making a significant decision (architecture, storage, data model, interface boundaries, dependency choice).
- Keep entries brief.
- Keep most recent decisions near the top.
- Lines below the first line must be indented by 4 spaces so they stay associated with the entry.

Entry format:
- Decision YYYY-MM-DD abcdef: Short title
    Decision: <what was chosen>
    Reason: <why it was chosen>
    Tradeoffs: <what is gained and what is lost>

<!-- ENTRIES START -->
- Decision 2026-01-12 9fd499c: Minimum supported macOS version
    Decision: Set the minimum supported macOS version to 15.7.
    Reason: This is the product requirement for the initial release.
    Tradeoffs: Older macOS versions are unsupported, which may exclude some users and reduces compatibility testing scope.

- Decision 2026-01-12 9fd499c: Generate Xcode project via XcodeGen
    Decision: Track `project.yml` and regenerate `ProjectWorkspaces.xcodeproj` via `scripts/regenerate_xcodeproj.sh` (XcodeGen) instead of editing `.pbxproj` by hand.
    Reason: Keep the Xcode project definition reviewable and avoid brittle manual edits and merge conflicts in the generated project file.
    Tradeoffs: Contributors must install `xcodegen` to change targets/settings; generated diffs can be large and require regeneration discipline.

- Decision 2026-01-11 9fd499c: Core target is a static framework
    Decision: Build `ProjectWorkspacesCore` as a static framework so `pwctl` can link it without requiring embedded runtime frameworks.
    Reason: A command-line tool does not embed dependent dynamic frameworks by default, which causes runtime loader failures during development.
    Tradeoffs: Static linking can increase binary size and can duplicate code between the app and CLI; switching to a dynamic framework later would require explicit embedding and runtime search path configuration.

- Decision 2026-01-11 000000: CLI-driven builds without Xcode UI
    Decision: Keep a single repo-level `ProjectWorkspaces.xcodeproj` (no `.xcworkspace` in v1) and drive build/test/archive/notarization via `xcodebuild -project` scripts (`scripts/dev_bootstrap.sh`, `scripts/build.sh`, `scripts/test.sh`, `scripts/archive.sh`, `scripts/notarize.sh`); commit the SwiftPM lockfile at `ProjectWorkspaces.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and resolve packages in CI; require the Apple toolchain (full Xcode) for developers/CI while keeping the Xcode GUI optional day-to-day.
    Reason: Deterministic builds/signing/notarization with minimal IDE friction and fewer “it works on my machine” differences.
    Tradeoffs: Additional script maintenance and occasional need to open Xcode for debugging/provisioning tasks.

- Decision 2026-01-11 000000: Config defaults and doctor severity
    Decision: Apply deterministic defaults for non-structural config omissions; Doctor FAIL only for structural/safety-critical issues and otherwise emit WARN/OK per spec, using Launch Services discovery for omitted IDE app fields; config parsing tolerates unknown keys so unsupported keys can be WARNed (not parse-failed).
    Reason: Keep the tool easy to configure and robust on a fresh machine without silent behavior.
    Tradeoffs: More defaulting behavior to document and test; warnings may be noisy.

- Decision 2026-01-11 000000: Log file contract and rotation
    Decision: Write to a single active log `workspaces.log` and rotate at 10 MiB with up to 5 archives (`workspaces.log.1`…`workspaces.log.5`).
    Reason: Preserve a stable “tail this file” contract while preventing unbounded growth.
    Tradeoffs: Older history rotates out; tooling may need to scan multiple files when diagnosing issues.

- Decision 2026-01-11 000000: Reserved fallback workspace pw-inbox
    Decision: Hard-code `pw-inbox` as the fallback workspace, forbid `project.id == "inbox"`, and have Doctor perform an AeroSpace connectivity check by switching to `pw-inbox` once.
    Reason: Make Close(Project) deterministic and ensure there is always a safe workspace to land on.
    Tradeoffs: Users cannot use `inbox` as a project id; Doctor performs a small workspace switch as part of validation.

- Decision 2026-01-11 000000: Dependency and hotkey policy
    Decision: Allow third-party Swift dependencies only for TOML parsing (SwiftPM, version pinned); hotkey is fixed to ⌘⇧Space and not configurable; if `global.switcherHotkey` is present it is ignored and Doctor emits WARN; if ⌘⇧Space cannot be registered, Doctor FAILs; implement the hotkey via Carbon `RegisterEventHotKey` with no third-party hotkey libraries.
    Reason: Minimize runtime dependencies while keeping parsing reliable and the hotkey implementation stable.
    Tradeoffs: More custom code in-house; the TOML dependency must be maintained and upgraded intentionally.

- Decision 2026-01-11 000000: CI test scope and opt-in integration tests
    Decision: Require unit tests in CI and gate real AeroSpace integration tests behind `RUN_AEROSPACE_IT=1` for local runs only.
    Reason: Real window manipulation and permissions are not reliably runnable in CI environments.
    Tradeoffs: Less end-to-end coverage in CI; engineers must run opt-in integration tests locally when changing AeroSpace/window behavior.

- Decision 2026-01-11 000000: Distribution channels
    Decision: Ship both a Homebrew cask (recommended) and a signed+notarized direct download artifact (`.zip` or `.dmg`) from a single canonical pipeline.
    Reason: Provide a smooth install/update path with a fallback for machines without Homebrew.
    Tradeoffs: More packaging complexity; the release process must keep the artifacts in sync.
