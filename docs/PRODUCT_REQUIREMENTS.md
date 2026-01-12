# ProjectWorkspaces — Product Requirements (PRD)

**Status:** Approved (locked)

**Purpose:** This document defines **what** ProjectWorkspaces must do (user-visible behavior, constraints, acceptance criteria) so engineers can implement without product/architecture decisions.

This PRD supersedes the older macOS-Spaces/pinning model from the original requirements spec and reflects the updated direction:

- **Container:** AeroSpace workspaces (virtual workspaces), not macOS Spaces
- **Lifecycle:** single **Activate** action (idempotent) instead of Open/Create separation
- **Chrome:** no pinned tabs, no extension; tabs are seeded only when the project Chrome window is (re)created
- **Close:** “Close Project” empties the project workspace by closing **every window** assigned to it

---

## 1. Problem

When working on many concurrent projects, window sprawl causes disorientation and makes context switching slow.

ProjectWorkspaces provides **project-first switching** by giving each project a stable, isolated “virtual workspace” containing:

- **One IDE window** (VS Code by default; Antigravity supported)
- **One dedicated Chrome window** for the project

---

## 2. Goals

### 2.1 Primary goals (MUST)

1) **Fast project switching** with low cognitive load
2) Each project has a stable workspace container (AeroSpace workspace)
3) Each project workspace reliably contains:
   - one IDE window
   - one Chrome window
4) **IDE ends focused** after activation (Chrome must not steal focus)
5) Support two display modes with persistent per-project layout:
   - laptop mode
   - ultrawide mode (5120×1440)
6) Repeatable installation and recovery on a fresh machine with:
   - explicit macOS permission requirements
   - a `doctor` command
   - clear logs

### 2.2 Secondary goals (SHOULD)

- Support both VS Code and Antigravity with the **same workflow**
- Allow per-project custom IDE launch commands (repo scripts)
- Allow “global apps” (Slack/Mail/Messages) to exist outside the project model (not managed; not required to be hidden)

---

## 3. Non-goals (explicit)

1) **No macOS Spaces pinning** (no Desk labels, no Mission Control navigation)
2) **No Open/Create toggle**; the UI only supports **Activate** and **Close**
3) **No Chrome pinned tabs** and no Chrome extension
4) **No enforced Chrome Profiles** per project
5) No multi-monitor orchestration as a product requirement
   - If multiple displays exist, behavior is best-effort and must warn in logs

---

## 4. Definitions

- **Project**: a configured unit of work (usually a local repo), identified by a stable `projectId`.
- **Workspace**: an **AeroSpace workspace** named `pw-<projectId>`.
- **Activate(Project)**: switch to the project workspace and ensure its core windows exist.
- **Close(Project)**: close every window in the project workspace.
- **Display mode**:
  - `laptop`: any main display width < `ultrawideMinWidthPx`
  - `ultrawide`: any main display width ≥ `ultrawideMinWidthPx`

---

## 5. Product surface area

### 5.1 App

- `ProjectWorkspaces.app`: a menu bar background agent (no Dock icon), always-on.

### 5.2 CLI

- `pwctl`: debugging and automation entry point

### 5.3 Files

- Config (source of truth): `~/.config/project-workspaces/config.toml`
- Generated VS Code workspace files: `~/.config/project-workspaces/vscode/<projectId>.code-workspace`
- Runtime state (cache): `~/.local/state/project-workspaces/state.json`
- Logs (active): `~/.local/state/project-workspaces/logs/workspaces.log`
- Logs (rotated): `~/.local/state/project-workspaces/logs/workspaces.log.1` … `~/.local/state/project-workspaces/logs/workspaces.log.5`

---

## 6. Functional requirements

### PR-001 — Project configuration

**MUST**

- Projects are defined exclusively via `config.toml`.
- Adding a new project must require editing only `config.toml`.
- `projectId` must match: `^[a-z0-9-]+$`.
- `projectId` must not be `inbox` (reserved for the fallback workspace `pw-inbox`).

### PR-002 — Config defaults, discovery, and doctor severity

**MUST**

- The tool must apply deterministic defaults for non-structural config omissions and surface omissions as Doctor WARN/OK (table below).
- Doctor must FAIL if any of the following are missing or invalid:
  - config file missing or TOML parse error
  - no `[[project]]` entries
  - any project has missing/invalid `id`, `name`, `path`, or `colorHex` (per PR-001)
  - required apps are not discoverable for the effective IDE selection(s) or Chrome
  - Accessibility permission is not granted (required for layout)
- If `ide.*.appPath` / `bundleId` are omitted, Doctor must attempt app discovery via Launch Services.
- Doctor must print discovered values as a copy/paste config snippet and must not auto-edit `config.toml`.
- Config parsing must tolerate unknown keys so that unsupported keys can be surfaced as WARN instead of becoming a parse failure (at minimum: tolerate `global.switcherHotkey` so it can be WARNed + ignored).
- If `global.switcherHotkey` is present, Doctor must WARN (“Hotkey is fixed to ⌘⇧Space; key is ignored; remove it.”) and runtime must ignore it.

Defaults (applied if keys are missing):

| Key                                | Default                       | Doctor severity when omitted |
| ---------------------------------- | ----------------------------- | ---------------------------- |
| `global.defaultIde`                | `"vscode"`                    | WARN                         |
| `global.globalChromeUrls`          | `[]`                          | WARN                         |
| `display.ultrawideMinWidthPx`      | `5000`                        | WARN                         |
| `project.ide`                      | inherit `global.defaultIde`   | WARN                         |
| `project.chromeUrls`               | `[]`                          | OK                           |
| `project.ideUseAgentLayerLauncher` | `true`                        | OK                           |
| `project.ideCommand`               | `""`                          | OK                           |

### PR-010 — Global switcher UI

**MUST**

- Global hotkey: **⌘⇧Space** opens the switcher.
- Hotkey is fixed to ⌘⇧Space and is not configurable.
- Switcher is keyboard-first:
  - type-to-filter
  - Enter = Activate
  - Esc = dismiss
- Switcher displays project identity:
  - color swatch
  - name

**MUST (Close)**

- In switcher, **⌘W** closes the selected project workspace (Close Project).

### PR-020 — Activate(Project) behavior

**MUST**

Given `projectId`:

1) Switch to workspace `pw-<projectId>`.
2) Ensure IDE window exists in that workspace.
   - If missing, create it.
3) Ensure Chrome window exists in that workspace.
   - If missing, create it.
4) Force IDE and Chrome windows to floating mode (to allow deterministic geometry).
5) Apply layout for the current display mode:
   - use persisted layout if available
   - otherwise use defaults
6) End with IDE focused.

**MUST**

- Activation is **idempotent**:
  - running it repeatedly must not create additional IDE/Chrome windows when the expected windows already exist.

### PR-030 — Close(Project) behavior (“close the workspace”)

**MUST**

- Close(Project) closes **every window assigned to the project’s AeroSpace workspace**.
- This is intentionally aggressive.
- If the user has windows configured “show on all desktops,” closing them may affect them globally. This is acceptable.
- After closing a currently focused project workspace, the app must switch to a fallback workspace:
  - `pw-inbox`
- `pw-inbox` is hard-coded and reserved (not configurable).

### PR-040 — Chrome behavior

**MUST**

- Exactly one Chrome window per project workspace.
- Chrome remains logged in normally (no enforced profiles).
- Tabs are seeded only when the project Chrome window is created/recreated:
  1) `global.globalChromeUrls`
  2) `project.repoUrl` (if set)
  3) `project.chromeUrls`
- After Chrome creation, the app must refocus the IDE.

### PR-050 — IDE behavior

**MUST**

- Supported IDEs: VS Code and Antigravity.
- Global default IDE exists with per-project override.

**MUST (custom launch)**

Per project, IDE launch priority is:

1) If `ideCommand` is non-empty: execute it in project root.
2) Else if `ideUseAgentLayerLauncher=true` and `./.agent-layer/open-vscode.command` exists: execute it in project root.
3) Else: open the generated `.code-workspace` with the configured IDE app.

**MUST (deterministic project identity in IDE)**

- The tool must generate a centralized `.code-workspace` file that applies project identity via VS Code workspace settings.
- If a custom launcher opens VS Code by folder, the tool must follow up by opening the generated workspace file in **reuse-window** mode so colors/settings apply.

**MUST (no assumptions about preconfigured CLIs)**

- The tool must not require users to manually install `code` into PATH.
- The tool must provide a tool-owned `code` shim when it needs to invoke VS Code CLI.

### PR-060 — Layout defaults

**MUST**

- Laptop mode:
  - IDE and Chrome are “maximized” (same visible frame; not macOS fullscreen)
  - IDE ends focused

- Ultrawide mode (5120×1440):
  - split visible frame into 8 equal vertical segments
  - segments 0–1 empty
  - segments 2–4 IDE
  - segments 5–7 Chrome
  - IDE ends focused

### PR-070 — Layout persistence

**MUST**

- Persist layout per project per display mode.
- If user resizes/moves IDE/Chrome, it must be saved (debounced) and restored on next Activate.

### PR-080 — Diagnostics and repeatability

**MUST**

- Provide `pwctl doctor` and an in-app “Run Doctor.”
- Doctor must validate:
  - AeroSpace installed/running and CLI resolvable
  - Accessibility permission granted to ProjectWorkspaces
  - Chrome installed
  - VS Code installed (and Antigravity if configured)
  - global hotkey ⌘⇧Space can be registered (FAIL if registration fails due to conflict / OS denial)
  - config parses and is valid
  - project paths exist
  - required directories are writable
- Doctor must perform an AeroSpace connectivity check by switching to `pw-inbox` once (and switching back best-effort).
- Failures must be actionable (explicit “Fix:” text).

### PR-090 — Logging

**MUST**

- The active log file path is stable: `~/.local/state/project-workspaces/logs/workspaces.log`.
- Rotate logs when the active log exceeds 10 MiB; keep `workspaces.log.1` through `workspaces.log.5` (max 5 archives).
- Every Activate and Close action must log:
  - timestamp
  - projectId
  - workspaceName
  - AeroSpace command invocations and stdout/stderr
  - final result (success/warn/fail)
- No silent failures.

---

## 7. Non-functional requirements

### NFR-001 — Reliability

- Activation must succeed in the common case without manual intervention.
- If it cannot succeed (missing permissions, missing app), errors must be explicit and actionable.

### NFR-002 — Performance

- Switcher must appear quickly.
- Activation should feel near-instant when windows already exist.

### NFR-003 — Security / system constraints

- Must not require SIP disabling.
- Must use documented macOS permissions (Accessibility) and make them explicit in setup.

### NFR-004 — Maintainability

- Config schema is versioned.
- State is a cache; deleting state must not destroy the ability to use the tool.

### NFR-005 — Distribution and toolchain

- End users must not be required to install Xcode.
- Developers and CI runners require the Apple build toolchain (practically: full Xcode installed).
- Common build/test/release workflows must be runnable from the command line (Xcode GUI optional day-to-day), using `xcodebuild`-driven scripts.
- The canonical repo entrypoint is `ProjectWorkspaces.xcodeproj` (no repo-level `.xcworkspace` in v1).
- Build/test scripts must use `xcodebuild -project ProjectWorkspaces.xcodeproj ...`.
- Introduce a repo-level `.xcworkspace` only if the repo contains 2+ `.xcodeproj` files that must be built together; if so, update scripts and record the migration in `docs/DECISIONS.md`.
- Commit `Package.resolved` for reproducible SwiftPM dependency resolution; CI must resolve packages before building (e.g., `xcodebuild -resolvePackageDependencies`).
- In this repo, the expected SwiftPM lockfile path is `ProjectWorkspaces.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (commit this file; do not add duplicate copies).
- The release artifact is a signed + notarized `.app`, shipped via both a Homebrew cask (recommended) and a direct download (`.zip` or `.dmg`).

### NFR-006 — Platform support

- The minimum supported macOS version is 15.7.

---

## 8. Acceptance criteria (end-to-end)

The product is acceptable when all tests below pass:

1) **Activate creates missing windows**
   - Starting from an empty workspace, Activate(Project) opens IDE and Chrome and ends with IDE focused.

2) **Activate is idempotent**
   - Re-running Activate does not create additional IDE/Chrome windows.

3) **Chrome focus rule**
   - After activation, IDE is focused even if Chrome was launched.

4) **Ultrawide layout default**
   - On 5120×1440, default layout uses the 2/8 empty + 3/8 IDE + 3/8 Chrome split.

5) **Layout persistence**
   - After user resizes, activation restores the custom geometry.

6) **Close empties the workspace**
   - Close(Project) closes every window in that project workspace.
   - Next Activate recreates missing windows.

7) **Doctor works**
   - On a fresh macOS machine, following README + Doctor results in a working system.

---

## 9. Future candidates (explicitly not committed)

These are possible later additions but are not part of v1 scope:

- Notifications / attention system
- Gesture invocation
- Support for additional browsers or IDEs
- Workspace templates beyond IDE+Chrome
