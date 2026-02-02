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

- Decision 2026-01-11 9fd499c: Core target is a static framework
    Decision: Build `AgentPanelCore` as a static framework so `ap` can link it without requiring embedded runtime frameworks.
    Reason: A command-line tool does not embed dependent dynamic frameworks by default, which causes runtime loader failures during development.
    Tradeoffs: Static linking can increase binary size; switching to dynamic later would require explicit embedding and runtime search path configuration.

- Decision 2026-01-11 9fd499c: Dependencies and hotkey policy
    Decision: Allow third-party Swift dependencies only for TOML parsing (`TOMLDecoder` pinned to 0.4.3 via SwiftPM); hotkey is fixed to ⌘⇧Space and not configurable; implement hotkey via Carbon `RegisterEventHotKey` with no third-party hotkey libraries.
    Reason: Minimize runtime dependencies while keeping parsing reliable and hotkey implementation stable.
    Tradeoffs: TOML dependency must be maintained; more custom code in-house for hotkey.

- Decision 2026-01-11 9fd499c: Logging contract
    Decision: Write JSON Lines log entries with UTC ISO-8601 timestamps to `agent-panel.log`; rotate at 10 MiB with up to 5 archives (`agent-panel.log.1`…`agent-panel.log.5`).
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

- Decision 2026-01-11 9fd499c: CI test scope
    Decision: Require unit tests in CI; do not run AeroSpace integration tests by default.
    Reason: Real window manipulation and permissions are not reliably runnable in CI environments.
    Tradeoffs: Less end-to-end coverage in CI; engineers must run integration checks locally when needed.

- Decision 2026-01-11 9fd499c: Distribution channels
    Decision: Ship both a Homebrew cask (recommended) and a signed+notarized direct download artifact from a single canonical pipeline.
    Reason: Provide a smooth install/update path with a fallback for machines without Homebrew.
    Tradeoffs: More packaging complexity; release process must keep artifacts in sync.

- Decision 2026-01-12 9fd499c: Minimum supported macOS version
    Decision: Set minimum supported macOS version to 15.7.
    Reason: Product requirement for initial release.
    Tradeoffs: Older macOS versions unsupported.

- Decision 2026-01-14 02e7dee: Skip hotkey check when agent runs
    Decision: Keep both `ap doctor` and in-app "Run Doctor"; skip hotkey registration check when the agent app is already running.
    Reason: Prevents false FAIL results during normal use when the agent already holds the hotkey.
    Tradeoffs: Hotkey check relies on agent detection.

- Decision 2026-01-25 f311f35: AeroSpace onboarding safe config
    Decision: Install a AgentPanel-safe AeroSpace config at `~/.aerospace.toml` only when no config exists; never modify existing configs; Doctor handles config state checks, safe installs, and emergency `aerospace enable off` action.
    Reason: Prevent tiling shock while preserving existing AeroSpace setups.
    Tradeoffs: Users with existing configs must opt into changes themselves.

- Decision 2026-01-26 24a9013: Extract Doctor checker structs
    Decision: Extract focused checker structs from Doctor.swift: PermissionsChecker (accessibility, hotkey), AppDiscoveryChecker (Chrome, IDEs), AeroSpaceChecker (all AeroSpace functionality). Doctor orchestrates checkers via composition.
    Reason: Doctor.swift had grown large with mixed responsibilities; extraction improves maintainability.
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
    Decision: Enumerate only `pw-<projectId>` for steady-state detection (no `list-windows --all`); allow focused-window recovery immediately after launch to capture the new window and move it into the workspace.
    Reason: Eliminates heavy global scans while still recovering from launch-time workspace misplacement.
    Tradeoffs: Focused recovery is time-bound and can fail if the new window never becomes focused.

- Decision 2026-01-27 b1f4c2d: Homebrew required for AeroSpace install
    Decision: Require Homebrew and only support AeroSpace installation via Homebrew for now; manual installs are deferred.
    Reason: Deterministic, scriptable install path for onboarding and Doctor automation.
    Tradeoffs: Users without Homebrew cannot onboard until a manual install path is added.

- Decision 2026-01-28 c3f1a9: Token-based window identification
    Decision: Identify Chrome and VS Code windows by deterministic token (`PW:<projectId>`) in window titles scoped to `pw-<projectId>`; avoid global scans; warn+choose lowest id on multiple matches; use focused-window recovery immediately after launch when a new window spawns outside the workspace.
    Reason: Deterministic identification without heavy scans, while still recovering from launch-time workspace misplacement.
    Tradeoffs: Window titles include a visible token; focused recovery is time-bound and can fail if the new window never becomes focused.

- Decision 2026-01-28 c3f1aa: VS Code workspace files in state dir
    Decision: Store generated `.code-workspace` files under `~/.local/state/agent-panel/vscode` and set `window.title` with the deterministic token.
    Reason: Keeps generated artifacts in state cache and enables deterministic VS Code window identification.
    Tradeoffs: Workspace files move from config to state; VS Code titles include a visible token.

- Decision 2026-01-28 8e2d6bf: Chrome launch uses open -na with optional profile directories
    Decision: Launch Chrome via `open -na` with `--window-name=PW:<projectId>` so window titles are deterministic; support optional per-project `chromeProfileDirectory` and surface available profile directory names in Doctor.
    Reason: Chrome ignores `--new-window/--window-name` when launched without `-n` on some machines; profile selection is required for deterministic behavior when multiple profiles are open.
    Tradeoffs: `-n` starts a new Chrome instance; profile configuration requires users to know Chrome profile directory names.

- Decision 2026-01-28 f7b2a1: Hotkey status overrides skip when agent runs
    Decision: When the agent app is running, Doctor uses the app-reported hotkey registration status (success/failure with OSStatus) when available; otherwise it skips the hotkey registration check.
    Reason: Avoid false failures while still surfacing real hotkey registration failures.
    Tradeoffs: Requires the agent to provide status; CLI Doctor may still skip when status is unavailable.

- Decision 2026-01-29 d4e7b9: Activation recovery timing and log timings
    Decision: Use a short workspace probe before focused-window recovery; treat list-windows timeouts/not-ready as retryable inside poll loops; log per-command start/end timestamps plus duration; treat floating-layout failures as warnings.
    Reason: Reduce perceived activation delay, avoid false failures from transient timeouts, and make activation timing diagnosable without guesswork.
    Tradeoffs: Poll timing is more complex; activation may report success with layout warnings that require manual correction.

- Decision 2026-01-29 5c2b7a: Display mode source and normalized layout space
    Decision: Define display mode using `CGMainDisplayID()` pixel width and map visible-frame geometry to the matching `NSScreen` display ID; normalized layout rectangles are relative to the visible-frame coordinate space.
    Reason: Provides deterministic main-display selection while avoiding pixel/point ambiguity in layout math.
    Tradeoffs: Multi-display behavior is anchored to the menu-bar display even if a focused window lives elsewhere.

- Decision 2026-01-29 7b1c0e: Unified state.json layout persistence
    Decision: Use a single versioned `state.json` schema that stores managed window IDs plus per-project per-display-mode layouts as normalized rects (`ide`/`chrome`) in visible-frame coordinates; persist via atomic temp-file rename with corruption backups.
    Reason: Prevents competing writers and keeps layout persistence deterministic across activation and observation.
    Tradeoffs: Schema changes require migration; corrupted files reset to empty state with a backup.
    Schema Example:
    ```json
    {
      "version": 1,
      "projects": {
        "codex": {
          "managed": {
            "ideWindowId": 400373,
            "chromeWindowId": 400375
          },
          "layouts": {
            "laptop": {
              "ide": {"x": 0, "y": 0, "width": 1, "height": 1},
              "chrome": {"x": 0, "y": 0, "width": 1, "height": 1}
            },
            "ultrawide": {
              "ide": {"x": 0.25, "y": 0, "width": 0.375, "height": 1},
              "chrome": {"x": 0.625, "y": 0, "width": 0.375, "height": 1}
            }
          }
        }
      }
    }
    ```

- Decision 2026-01-29 3d8f9a: AX/AppKit coordinate conversion
    Decision: Convert AppKit bottom-left frames to AX top-left positions (and back) using the main display height, with round-trip tests.
    Reason: Avoids Y-axis inversion bugs when applying and persisting AX window geometry.
    Tradeoffs: Assumes main-display coordinate space; multi-display remains main-display only.

- Decision 2026-01-29 016c408: Switcher dismisses before activation
    Decision: The switcher dismisses immediately on Enter and activation starts on the next runloop tick; ActivationService owns focus and no UI layer re-asserts focus.
    Reason: Avoids focus churn while the panel is key and keeps activation semantics consistent across switcher and CLI.
    Tradeoffs: Switcher no longer shows an in-panel busy state; failures must surface outside the switcher.

- Decision 2026-01-30 3f9c1b2: Switcher stays visible during activation
    Decision: The switcher remains visible as a non-key HUD during activation; Chrome is ensured before IDE; workspace existence uses `list-workspaces`; window detection timeouts are increased by +5s.
    Reason: Provide continuous user feedback during slow activations while avoiding focus contention.
    Tradeoffs: Requires careful HUD focus handling and longer waits before failure; supersedes 2026-01-29 016c408.

- Decision 2026-01-30 fallback: All-workspaces fallback for Chrome detection
    Decision: Add a last-resort fallback in ChromeLauncher that checks ALL workspaces (`list-windows --all`) for the tokened Chrome window when both workspace-specific and focused-window detection time out.
    Reason: Chrome may create windows in a workspace other than the focused one and not gain focus, causing detection to fail despite the window existing.
    Tradeoffs: Adds one global scan as a fallback; still prefers workspace-specific and focused detection first; partially supersedes 2026-01-27 e7c3a1b (no global scans) by allowing a fallback scan on timeout.

- Decision 2026-01-30 parallel: Parallel Chrome/IDE launch with sequential detection
    Decision: Launch Chrome first (fire and forget), then immediately launch IDE, wait for IDE detection first, then wait for Chrome detection; switcher panel uses `canJoinAllSpaces` behavior and calls `focusWorkspaceAndWindow` after dismiss.
    Reason: Improves perceived activation speed by launching both apps in parallel while ensuring IDE is detected and focused first; reverts panel behavior to `canJoinAllSpaces` which provides more reliable cross-workspace visibility; adds explicit post-dismiss focus to ensure IDE receives focus after switcher closes.
    Tradeoffs: Chrome detection happens after IDE detection, so Chrome errors surface later; adds complexity to ChromeLauncher with separate check/launch/detect methods; partially supersedes 2026-01-30 3f9c1b2 (Chrome before IDE sequential) by making launch parallel.

- Decision 2026-01-31 7c2d4f1: Core/App boundary via WorkspaceManaging facade
    Decision: App code depends on the Core `WorkspaceManaging` facade for activation and focus operations; AeroSpace focus probing and client creation live behind Core's `WorkspaceFocusProviding`.
    Reason: Enforces a minimal, stable interface between App and Core and keeps AeroSpace details out of the UI layer.
    Tradeoffs: Adds an abstraction layer and centralizes focus behavior in Core, so UI-level tweaks must flow through Core APIs.

- Decision 2026-01-31 8f3a2b: AeroSpace list-workspaces requires explicit scope flag
    Decision: `AeroSpaceClient.listWorkspaces()` uses `--all` flag; upstream AeroSpace requires one of `--all`, `--focused`, or `--monitor` for `list-workspaces`.
    Reason: AeroSpace CLI contract requires explicit scope; omitting the flag causes command failure.

- Decision 2026-01-31 9e4b3c: State file atomic replacement uses replaceItemAt
    Decision: StateStore.save() uses `FileManager.replaceItemAt` when the destination file exists, falling back to `moveItem` for first-time saves.
    Reason: `moveItem` fails if the destination exists; `replaceItemAt` handles atomic replacement correctly.
    Tradeoffs: Adds a conditional path for first-time vs subsequent saves; `replaceItemAt` is the correct Foundation API for atomic replacement.

- Decision 2026-01-31 5c0d7a1: Layout waits for focused workspace before AX convergence
    Decision: LayoutCoordinator waits up to 2s for the expected workspace to become focused before reading AX geometry; if focus does not settle, it skips AX convergence, applies layout deterministically, and suppresses off-main-display warnings.
    Reason: AeroSpace hides inactive workspace windows off-screen; waiting for focus avoids false off-screen warnings and reduces layout churn.
    Tradeoffs: Adds a short focus wait and new warnings when focus does not settle; layout may proceed without AX frame reads in that case.

- Decision 2026-02-01 6a1f4c2: CLI-only AeroSpace activation and deterministic layout
    Decision: Activation uses the AeroSpace CLI as the sole source of truth (no AX geometry), confirms focus via `list-workspaces --focused`, resolves exactly one IDE + Chrome window on the focused monitor, moves them to the target workspace, and always reapplies the canonical layout (flatten, balance, h_tiles) with deterministic IDE width computed from the focused monitor's visible width; all AeroSpace commands are serialized; activation failures are hard errors with no warning state.
    Reason: Aligns with AeroSpace's hidden-window model and removes noisy geometry-based warnings while making activation deterministic and debuggable.
    Tradeoffs: Stricter activation that fails on ambiguity; increased reliance on AeroSpace CLI availability and app-provided screen metrics; supersedes prior AX-based layout and window-detection decisions.

- Decision 2026-02-01 4d9b7e1: StateStore saves always use replaceItemAt
    Decision: StateStore writes always replace the destination using `FileManager.replaceItemAt`, even on first write, via the FileSystem abstraction.
    Reason: `replaceItemAt` provides atomic replacement and avoids the error-prone `moveItem` path.
    Tradeoffs: Relies on `replaceItemAt` behavior for non-existent destinations; supersedes the earlier conditional move/replace decision.

- Decision 2026-02-02 5a7c2e9: Doctor helpers live in ApDoctor.swift
    Decision: Inline PermissionsChecker and AppDiscoveryChecker into ApDoctor.swift and keep Doctor-only helper logic co-located there.
    Reason: Reduce file count while keeping Doctor-only functionality in one place.
    Tradeoffs: ApDoctor.swift grows larger; reverses the extracted-checkers structure from 2026-01-26 24a9013.

- Decision 2026-02-02 8c2a9d1: Remove emergency disable AeroSpace action
    Decision: Remove the Doctor/UI action that runs `aerospace enable off` ("Emergency: Disable AeroSpace") and drop the corresponding action availability state.
    Reason: The project no longer wants to support or advertise disabling AeroSpace window management via AgentPanel.
    Tradeoffs: Fewer recovery options inside AgentPanel; users must manage AeroSpace state directly when needed.

- Decision 2026-02-02 1f6c3e7: Remove Accessibility permission requirement
    Decision: Remove Accessibility checks from Doctor and drop the Accessibility permission requirement for AgentPanel.
    Reason: The current app behavior does not use AX APIs; keeping the requirement was unnecessary friction.
    Tradeoffs: If AX-based window manipulation returns later, the check must be reintroduced.

- Decision 2026-02-01 2b7d9e0: Remove legacy launch + layout persistence pipeline
    Decision: Removed the legacy IDE/Chrome launch pipeline, token-based window detection, layout defaults/persistence, and StateStore; activation is CLI-only and requires pre-opened IDE/Chrome windows.
    Reason: Those paths are unused in the CLI-only activation flow and were creating dead code and stale docs.
    Tradeoffs: Configuration keys remain but are unused; reintroducing launch automation or layout persistence will require new dedicated work; supersedes 2026-01-28 c3f1a9/c3f1aa/8e2d6bf and 2026-01-29 7b1c0e/3d8f9a plus 2026-01-31 9e4b3c and 2026-02-01 4d9b7e1.

- Decision 2026-02-01 d2e9f4a: Remove legacy launch config keys and discovery
    Decision: Removed legacy IDE/Chrome launch config keys and discovery (global Chrome URL lists, repo URL seeding, display ultrawide config, IDE launch overrides, Chrome URL/profile settings), along with Chrome profile discovery and unused state/workspace path helpers; config schema now only includes `global.defaultIde`, `ide.*` app discovery values, and per-project `id/name/path/colorHex/ide`.
    Reason: CLI-only activation relies on pre-existing windows and explicit AeroSpace layout steps; keeping unused launch keys and discovery logic is misleading and increases maintenance surface.
    Tradeoffs: Users can no longer specify launch-time IDE/Chrome options; the prior "keys remain but unused" tradeoff is superseded by removal.

- Decision 2026-02-01 b8c2f6a: Binding-based activation with auto-open windows
    Decision: Activation now uses per-project bindings (one IDE + one Chrome), prunes stale bindings using `list-windows --all --json`, opens a new window for any missing role, moves only bound windows, and focuses the IDE; workspace focus uses `summon-workspace` and canonical layout is applied only when the workspace had no bound windows present.
    Reason: Supports multiple IDE/Chrome windows in the system while keeping activation deterministic and ensuring unbound windows are untouched.
    Tradeoffs: Requires binding state persistence and token-based detection for newly opened windows; supersedes the earlier "pre-opened windows only" requirement in 2026-02-01 6a1f4c2/2b7d9e0, workspace-only enumeration in 2026-01-27 a6d2f1b/e7c3a1b, and the launch-key removal in 2026-02-01 d2e9f4a.

- Decision 2026-02-01 9a7c1de: Remove unused display config
    Decision: Drop `display.ultrawideMinWidthPx` and related parsing/docs; `[display]` is now treated as an unknown config key.
    Reason: The display config was unused and created dead code plus misleading documentation.
    Tradeoffs: Existing configs with `[display]` will emit unknown-key warnings until updated.

- Decision 2026-02-02 b4d9e2: AgentPanel reset and activation removal
    Decision: Remove activation/workspace management and the legacy CLI; keep Doctor/config/logging/paths and a list-only switcher; `ap` is the CLI entrypoint.
    Reason: Focus on the ap stack and establish a clean baseline while preserving Doctor and config validation.
    Tradeoffs: No project activation; switcher selection only logs until activation is rebuilt.

- Decision 2026-02-02 a8c2d4f: Doctor AeroSpace checks now use apcore
    Decision: Doctor uses `apcore`'s `ApAeroSpace` for CLI readiness (`list-workspaces --focused`) and compatibility (single `--help` flag audit) and no longer performs workspace-switch tests; config state checks remain in Doctor.
    Reason: Keep AeroSpace command knowledge in apcore and avoid intrusive workspace switching during Doctor.
    Tradeoffs: Loses a direct workspace-switch integration check; readiness now only confirms CLI responsiveness.
