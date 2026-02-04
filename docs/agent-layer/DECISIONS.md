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

- Decision 2026-02-03 appkit: AppKitIntegration duplication is intentional
    Decision: Both `AgentPanelCLI/AppKitIntegration.swift` and `AgentPanelApp/AppKitIntegration.swift` contain a `RunningApplicationChecking` protocol and `AppKitRunningApplicationChecker` implementation. This duplication is kept intentionally.
    Reason: `AgentPanelCore` is a static framework that cannot import AppKit (it is shared between the CLI and GUI targets). Both targets need `NSRunningApplication` API for Doctor checks. Duplicating the implementation allows each target to compile independently while maintaining API compatibility.
    Tradeoffs: Must keep both files in sync manually; any changes to the protocol or implementation require updates in both locations.

- Decision 2026-02-03 guipath: GUI apps don't inherit shell PATH
    Decision: Use `ExecutableResolver` to find executables instead of `/usr/bin/env`. Searches standard paths first, falls back to login shell `which`.
    Reason: GUI apps launched via Finder/Dock get a minimal PATH without Homebrew or user additions. `/usr/bin/env` fails to find `code`, `brew`, `aerospace`, etc.
    Tradeoffs: Must maintain search path list; zsh fallback has performance cost.

- Decision 2026-02-03 pipes: Read pipes concurrently to avoid deadlock
    Decision: Use `readabilityHandler` to stream stdout/stderr while process runs, not after termination.
    Reason: Pipe buffers are ~64KB. If a process fills the buffer and blocks, waiting for termination before reading creates a deadlock.
    Tradeoffs: More complex thread synchronization.
