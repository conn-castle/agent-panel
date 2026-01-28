# ProjectWorkspaces — Implementation Roadmap

This roadmap captures the implementation plan and major architectural decisions so engineers can implement without design decisions. The agent-layer ROADMAP is the active execution plan; if they diverge, surface the conflict for user guidance.

## Scope baseline (what we are building)

We are building a macOS project workspace switcher that:

- Uses **AeroSpace workspaces** as the only workspace container (not macOS Spaces).
- Implements a single primary action: **Activate(project)**
  - Switch to the project’s workspace
  - Ensure the project’s **IDE window** exists (create if missing)
  - Ensure the project’s **Chrome window** exists (create if missing)
  - Apply the project’s saved layout for the current display mode (or defaults)
  - End with the IDE focused
- Provides a global keyboard-first switcher invoked by **⌘⇧Space**.
- Provides a **Close Project** action that closes **every window in the project’s AeroSpace workspace** (closing the workspace by emptying it).
- Persists per-project per-display-mode layout (laptop vs ultrawide).

This roadmap is derived from the requirements spec but intentionally changes the prior “macOS Space pinning” and “Open/Create separation” into an “Activation” model.

## Non-goals (explicit)

- No macOS Spaces pinning, desk labels, or Mission Control navigation.
- No Chrome pinned tabs, no Chrome extension.
- No forced Chrome Profile isolation (per-project profile selection is optional).
- No multi-monitor orchestration. If multiple displays are present, behavior is best-effort and the app should show a warning.

## Key design decisions (locked)

1) **Container**: AeroSpace workspaces only.
2) **Primary UX**: Activation model only (no Open/Create split).
3) **Switcher hotkey (fixed)**: ⌘⇧Space.
4) **Display modes**: exactly two
   - `laptop`
   - `ultrawide` (Nick’s ultrawide is 5120×1440)
5) **Workspace file storage**: centralized, tool-owned
   - `~/.local/state/project-workspaces/vscode/<projectId>.code-workspace`
6) **Tab seeding**: only when Chrome window is (re)created; no enforcement afterwards.
7) **Close Project**: closes **all windows** in that project workspace.
8) **No per-repo gitignore requirement**.
9) **Implementation language**: Swift.
   - Rationale: stable TCC/Accessibility permissions, reliable global hotkeys, distribution as a signed/notarized app.
10) **Dependency policy**: Third-party Swift dependencies are allowed only for TOML parsing (SwiftPM, version pinned).
11) **Hotkey implementation**: Apple-only via Carbon `RegisterEventHotKey` (no third-party hotkey libraries).
12) **Test policy**: CI runs unit tests only; AeroSpace integration tests are local-only behind `RUN_AEROSPACE_IT=1`.
13) **Logs contract**: Single active log file with deterministic rotation (rotate at 10 MiB, keep 5 archives).
14) **Fallback workspace**: `pw-inbox` is hard-coded and reserved; `projectId == "inbox"` is invalid and Doctor performs a connectivity check by switching to `pw-inbox` once.
15) **AeroSpace onboarding**: Install a ProjectWorkspaces-safe config at `~/.aerospace.toml` only when no config exists; never modify existing configs; do not use config-based window moving; provide an emergency `aerospace enable off` action.
16) **Build workflow**: Keep a single `ProjectWorkspaces.xcodeproj` in-repo and drive builds/tests/archives via `xcodebuild -project` scripts so the Xcode GUI is not required day-to-day.
17) **Toolchain requirement**: End users do not need Xcode; developers and CI runners require the Apple toolchain (practically: full Xcode installed).
18) **Workspace policy**: Do not add a repo-level `.xcworkspace` in v1; introduce it only if the repo contains 2+ `.xcodeproj` files that must be built together (record the migration in `docs/agent-layer/DECISIONS.md` and update scripts).
19) **SwiftPM reproducibility**: Commit `ProjectWorkspaces.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and ensure CI resolves packages before building (for example via `xcodebuild -resolvePackageDependencies`).

## Definitions

- **Project**: Configured unit of work (typically a repo) identified by `projectId`.
- **Workspace**: An AeroSpace workspace named `pw-<projectId>`.
- **Activation**: Enter project context and ensure required windows exist.
- **IDE**: VS Code or Antigravity.

## Repository deliverables

- `ProjectWorkspaces.app` — menu bar agent (LSUIElement) with switcher UI.
- `pwctl` — optional CLI wrapper for scripting/debugging.
- `doctor` — surfaced through `pwctl doctor` and an in-app “Run Doctor” (both entry points are permanent).

## File system contract (locked)

- Config: `~/.config/project-workspaces/config.toml`
- Generated VS Code workspace files: `~/.local/state/project-workspaces/vscode/*.code-workspace`
- State: `~/.local/state/project-workspaces/state.json`
- Logs (active): `~/.local/state/project-workspaces/logs/workspaces.log`
- Logs (rotated): `~/.local/state/project-workspaces/logs/workspaces.log.1` … `~/.local/state/project-workspaces/logs/workspaces.log.5` (rotate at 10 MiB)

## Config schema (locked)

`~/.config/project-workspaces/config.toml`

Switcher hotkey is fixed to ⌘⇧Space and is not configurable. If `global.switcherHotkey` is present, Doctor emits WARN and the key is ignored (remove it).

```toml
[global]
defaultIde = "vscode"                 # optional; default "vscode" ("vscode" | "antigravity")

# Tabs opened only when a project Chrome window is created
globalChromeUrls = [
  "https://chatgpt.com/",
  "https://gemini.google.com/",
  "https://claude.ai/",
  "https://todoist.com/app"
]

[display]
ultrawideMinWidthPx = 5000            # optional; default 5000

[ide.vscode]
appPath = "/Applications/Visual Studio Code.app"  # optional; omit to auto-discover via Launch Services
bundleId = "com.microsoft.VSCode"                 # optional; omit to auto-discover via Launch Services

[ide.antigravity]
appPath = "/Applications/Antigravity.app"         # optional; omit to auto-discover via Launch Services
# bundleId omitted on purpose; doctor can discover and print it as a copy/paste snippet

[[project]]
id = "codex"
name = "Codex"
path = "/Users/nick/src/codex"
colorHex = "#7C3AED"
repoUrl = "https://github.com/ORG/REPO"  # optional
ide = "vscode"                           # optional; defaults to global.defaultIde (Doctor WARN when omitted)

# IDE launching
ideUseAgentLayerLauncher = true           # optional; default true
ideCommand = ""                           # optional; default ""

# Additional Chrome tabs for this project (only used at Chrome creation)
chromeUrls = []                           # optional; default []
chromeProfileDirectory = "Profile 2"      # optional; Chrome profile directory (see Doctor)
```

### Defaults and doctor severity (locked)

Defaults are required so the tool is easy to configure on a fresh machine. Only structural/safety-critical omissions are Doctor FAIL; everything else uses a deterministic default and is surfaced as Doctor WARN/OK.

Config parsing must tolerate unknown keys (at minimum: tolerate `global.switcherHotkey`) so Doctor can WARN and ignore removed/unsupported keys.

Doctor FAIL if missing/invalid:
- Config file missing or TOML parse error
- No `[[project]]` entries
- Any project missing/invalid: `id` (regex + unique + not `inbox`), `name` (non-empty), `path` (exists), `colorHex` (`#RRGGBB`)
- Required apps not discoverable for the effective IDE selection(s) or Chrome (using Launch Services discovery if config values are omitted)
- Accessibility permission not granted (required for layout)
- Unable to register the global hotkey ⌘⇧Space (conflict / OS denial); if the agent app is running, skip this check and report PASS with a note.

Doctor WARN if present:
- `global.switcherHotkey` (ignored; hotkey is fixed to ⌘⇧Space)

Defaults (applied if keys are missing):

| Key                                | Default                     | Doctor severity when omitted |
| ---------------------------------- | --------------------------- | ---------------------------- |
| `global.defaultIde`                | `"vscode"`                  | WARN                         |
| `global.globalChromeUrls`          | `[]`                        | WARN                         |
| `display.ultrawideMinWidthPx`      | `5000`                      | WARN                         |
| `project.ide`                      | inherit `global.defaultIde` | WARN                         |
| `project.chromeUrls`               | `[]`                        | OK                           |
| `project.chromeProfileDirectory`   | unset                       | OK                           |
| `project.ideUseAgentLayerLauncher` | `true`                      | OK                           |
| `project.ideCommand`               | `""`                        | OK                           |

### Workspace naming

- Workspace name is always: `pw-<projectId>`
- `projectId` must match regex: `^[a-z0-9-]+$` (enforced by doctor and runtime)
- `projectId` must not be `inbox` (reserved for the fallback workspace `pw-inbox`).

## State schema (locked)

`~/.local/state/project-workspaces/state.json`

```json
{
  "version": 1,
  "projects": {
    "codex": {
      "workspaceName": "pw-codex",
      "layouts": {
        "laptop": {
          "ide": {"x": 0, "y": 0, "w": 1440, "h": 900},
          "chrome": {"x": 0, "y": 0, "w": 1440, "h": 900}
        },
        "ultrawide": {
          "ide": {"x": 1280, "y": 0, "w": 1920, "h": 1440},
          "chrome": {"x": 3200, "y": 0, "w": 1920, "h": 1440}
        }
      }
    }
  }
}
```

Notes:
- State is a cache and may be deleted without data loss (config is source of truth).
- No window IDs are persisted across runs (avoid stale-window failure modes).

---

## Phases

### Phase 0 — Project scaffold + contracts + doctor skeleton

**Objective:** Create a runnable macOS agent app skeleton, lock file paths, lock config parsing, and implement `doctor` with actionable output.

**Deliverables**

1) Xcode project(s):
   - `ProjectWorkspacesApp` (SwiftUI, menu bar)
   - `ProjectWorkspacesCore` (pure Swift module)
   - `pwctl` (Swift command-line tool)

2) CLI-driven build workflow (no Xcode UI required day-to-day):
   - Provide `scripts/dev_bootstrap.sh` to validate the Xcode toolchain is installed/selected (`xcode-select`) and fail loudly with fix instructions.
   - Provide `scripts/build.sh` and `scripts/test.sh` that call `xcodebuild -project ProjectWorkspaces.xcodeproj ...` with deterministic schemes/configuration.
   - Commit `ProjectWorkspaces.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and ensure CI resolves packages before building (for example via `xcodebuild -resolvePackageDependencies`).
   - Allow developers to edit code in VS Code (or any editor); opening Xcode is optional.

3) Config parsing and validation (TOML):
   - Parse `config.toml` into typed models with explicit defaults and tolerant unknown-key handling (unknown keys must not cause a parse failure).
   - Validate required per-project fields:
     - `id` matches `^[a-z0-9-]+$`, is unique, and is not `inbox`
     - `name` is non-empty
     - `path` exists
     - `colorHex` matches `#RRGGBB`
   - Resolve effective IDE per project: `project.ide` defaults to `global.defaultIde`, which defaults to `"vscode"`.

4) Doctor (MVP):
   - Checks:
     - Config file exists and parses
     - At least one `[[project]]` exists
     - Homebrew installed (required for AeroSpace install; manual installs deferred)
     - AeroSpace installed (binary exists)
     - `aerospace` CLI callable (resolve absolute path)
     - AeroSpace config state (missing / existing / ambiguous) checked before server start
     - Safe config install at `~/.aerospace.toml` when no config exists (marker required, atomic write)
     - Never modify an existing AeroSpace config; fail if configs are ambiguous
     - Accessibility permission status (for the agent app)
     - Chrome installed
     - VS Code installed (Antigravity optional)
     - Global hotkey ⌘⇧Space can be registered (FAIL if registration fails due to conflict / OS denial)
     - Warn on ignored config keys (for example: `global.switcherHotkey`)
     - Required apps are discoverable for the effective IDE selection(s) and Chrome (use Launch Services discovery if config values are omitted)
     - Reserved ID validation: FAIL if any `project.id == "inbox"`
     - AeroSpace connectivity check by switching to `pw-inbox` once (switch back best-effort)
     - Report the loaded AeroSpace config path via `aerospace config --config-path`
     - Emergency action: `aerospace enable off`
     - Workspace directory write access
   - Output format: list of PASS/FAIL/WARN with a “Fix” line and a report header (timestamp, version, macOS, AeroSpace app/CLI paths).

**Exit criteria**

- `pwctl doctor` runs and returns non-zero if any FAIL exists.
- `scripts/build.sh` and `scripts/test.sh` work end-to-end from the CLI on a developer machine with Xcode installed.
- A new developer can clone repo, run app, run doctor, and see actionable guidance.

---

### Phase 1 — AeroSpace client wrapper + window enumeration primitives

**Objective:** Establish a reliable, testable AeroSpace integration layer.

**Deliverables**

1) `AeroSpaceClient` that runs these commands:
   - `aerospace workspace <name>`
   - `aerospace list-windows --workspace <name> --json --format '%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title}'`
   - `aerospace list-windows --all --json --format '%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title}'`
   - `aerospace focus --window-id <id>`
   - `aerospace move-node-to-workspace --window-id <id> <workspace>`
   - `aerospace layout floating --window-id <id>`
   - `aerospace close --window-id <id>`

2) JSON decoding for list-windows output.

3) Robust execution:
   - Timeouts
   - Structured error output including stdout/stderr
   - Retry policy for “AeroSpace not ready” failures (max 20 attempts, 50ms initial, 1.5x backoff, 750ms cap, 5s total, +/-20% jitter)

**Exit criteria**

- CI-required unit tests cover JSON decoding and CLI wrapper behavior using fixtures/mocks.
- When `RUN_AEROSPACE_IT=1`, a local integration test can:
  - create/focus a workspace
  - enumerate windows
  - focus a window by id
- No hardcoded PATH assumptions; binary path resolved once at startup.

---

### Phase 2 — VS Code workspace file generation + IDE launch pipeline

**Objective:** Make IDE window creation deterministic and apply project color identity.

**Deliverables**

1) Workspace file generator:
   - Writes `~/.local/state/project-workspaces/vscode/<projectId>.code-workspace`
   - Includes:
     - `folders: [{ path: <project.path> }]`
     - `settings.workbench.colorCustomizations` derived from `project.colorHex`
     - `settings.window.title` with a deterministic token (`PW:<projectId>`)

2) IDE launch strategy (per project):
   - Working directory is always project root.
   - Launch priority:
     1) If `ideCommand` non-empty → run via `/bin/zsh -lc`.
     2) Else if `ideUseAgentLayerLauncher=true` and `<repo>/.agent-layer/open-vscode.command` exists → run it.
     3) Else open the effective IDE:
        - VS Code: `open -a <VSCode.appPath> <workspaceFile>`
        - Antigravity: `open -a <Antigravity.appPath> <workspaceFile>`
   - `ideCommand`/launcher always receives: `PW_PROJECT_ID`, `PW_PROJECT_NAME`, `PW_PROJECT_PATH`, `PW_WORKSPACE_FILE`, `PW_REPO_URL`, `PW_COLOR_HEX`, `PW_IDE`, `OPEN_VSCODE_NO_CLOSE=1`.
   - If `ideCommand`/launcher exits non-zero, log WARN and fall back to the effective IDE open command; if the fallback open fails, activation fails with an actionable error.

3) VS Code “color enforcement” after custom launch:
   - After any VS Code launch (including fallback), ensure the workspace file is opened in the IDE by running VS Code CLI with reuse-window against the workspace file.
   - Implement a tool-owned `code` shim so VS Code CLI is available without manual setup.
     - Install to: `~/.local/share/project-workspaces/bin/code`
     - The shim invokes the VS Code bundled CLI within the VS Code app bundle.
     - The agent sets PATH to include this shim directory when running custom commands.

4) Antigravity support:
   - Uses same workspace file.
   - No Antigravity CLI assumptions; fallback is `open -a <Antigravity.appPath> <workspaceFile>`.

**Exit criteria**

- Activating a project with no IDE window successfully opens the IDE.
- IDE color identity is visible and stable when the project is activated.
- `ideCommand` and agent-layer launcher both work; failures fall back to opening the effective IDE and fail if the fallback open fails.

---

### Phase 3 — Chrome window creation + tab seeding (no pinning)

**Objective:** Ensure one Chrome window exists for the project and seed its tabs only on creation.

**Deliverables**

1) Chrome launch behavior:
   - When a project’s Chrome window is missing, create it with tabs:
     - Global tabs (`global.globalChromeUrls`)
     - If `repoUrl` set, add it as a tab
     - Project tabs (`project.chromeUrls`)
   - Tabs are opened by launching Chrome with `open -na "Google Chrome" --args --new-window --window-name="PW:<projectId>"` and URLs.
   - If `project.chromeProfileDirectory` is set, include `--profile-directory="<dir>"` in the launch args.
   - No tab enforcement after creation.

2) Window identification:
   - Detect Chrome windows by matching a deterministic token in `aerospace list-windows --all --json --format '%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title}'`.
   - Exactly one token match is required; zero or multiple matches fail loudly.

3) Focus rule:
   - Always end activation by focusing IDE window (Chrome must not steal focus).

**Exit criteria**

- If Chrome window is closed, activation recreates it with the expected tabs.
- Activation ends with IDE focused every time.

---

### Phase 4 — Activation engine (single action)

**Objective:** Implement `Activate(projectId)` end-to-end.

**Algorithm (must match exactly)**

1) Switch to workspace `pw-<projectId>`.
2) Enumerate windows in the workspace for baseline; token-based scans may use `list-windows --all`.
3) Ensure IDE window exists:
   - VS Code: match the `PW:<projectId>` token; move to `pw-<projectId>` if needed; fail on zero or multiple matches.
4) Ensure Chrome window exists:
   - Match the same token in Chrome window titles; move to `pw-<projectId>` if needed; create if missing; fail on zero or multiple matches.
5) Force both windows to floating.
6) Apply layout (Phase 5).
7) Focus IDE.

**Exit criteria**

- `pwctl activate <projectId>` is idempotent: running twice does not create extra IDE/Chrome windows.
- Missing-window recovery works.

---

### Phase 5 — Switcher UI + global hotkey

**Objective:** Provide the user-facing experience.

**Deliverables**

1) Switcher UI:
   - Invoked by ⌘⇧Space.
   - Hotkey implementation uses Carbon `RegisterEventHotKey` (no third-party hotkey libraries).
   - Type-to-filter.
   - Shows: color swatch + project name.
   - Enter activates.
   - Escape closes.

2) Additional action: Close Project
   - Shortcut: ⌘W closes selected project (see Phase 7 behavior).

3) No Open/Create toggle.

**Exit criteria**

- Switcher is usable entirely from keyboard.
- Invoking from any app works.

---

### Phase 6 — Layout engine + persistence

**Objective:** Implement layout defaults and per-project persistence for laptop vs ultrawide.

**Display mode detection (locked)**

- If main display width >= `display.ultrawideMinWidthPx` → `ultrawide`
- Else → `laptop`

**Default layouts (locked)**

- Laptop:
  - Both IDE and Chrome frames = screen visible frame.
  - Focus IDE.

- Ultrawide (8 segments):
  - Segment width = `visibleFrame.width / 8`
  - Empty: segments 0–1
  - IDE: segments 2–4
  - Chrome: segments 5–7
  - Full height.
  - Focus IDE.

**Persistence (locked)**

- Persist per project per display mode in state.json.
- Save on window move/resize (debounced 500ms).

**How window geometry is applied (locked)**

- Use Accessibility (AX) APIs to set window position/size.
- Avoid mapping window-id → AXWindow directly by using:
  - `aerospace focus --window-id <id>`
  - then read/write the system “focused window” via AX as the target.

**Exit criteria**

- Resizing windows in a project persists and is restored on next activation in the same display mode.

---

### Phase 7 — Close Project (close workspace by emptying it)

**Objective:** Provide a reliable “close workspace” action.

**Behavior (locked)**

- Close Project closes **every window assigned to the project’s AeroSpace workspace**.
- If a window belongs to an app that is “show on all desktops,” closing it may close it globally. This is an acceptable side effect.

**Algorithm (locked)**

1) Enumerate windows in workspace `pw-<projectId>`.
2) For each window id (sorted ascending): `aerospace close --window-id <id>`
3) After closing, switch to `pw-inbox` if the closed workspace was focused.

**Exit criteria**

- Close Project removes all windows from the project workspace.
- Next activation recreates missing IDE/Chrome windows as needed.

---

### Phase 8 — Packaging + onboarding + documentation polish

**Objective:** Make the tool easy to install and hard to misconfigure.

**Deliverables**

- Signed + notarized `ProjectWorkspaces.app`, distributed via both Homebrew cask (recommended) and direct download (`.zip` or `.dmg`).
- Release scripts (not yet implemented): `scripts/archive.sh` and `scripts/notarize.sh` will drive `xcodebuild archive/export`, notarization, and stapling (no Xcode UI required).
- `pwctl` shipped alongside.
- README finalized (install/config/usage/troubleshooting).
- Doctor covers the complete setup, including Accessibility.

**Exit criteria**

- A fresh macOS machine can be set up using README alone.
- Doctor reports no FAIL on a correctly configured machine.
