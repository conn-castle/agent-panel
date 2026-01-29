# Project Windows

## Principles
- No guessing. Only act on windows that are deterministically identified as ProjectWorkspaces-owned.
- No fallbacks. If a window cannot be identified with certainty, fail loudly.
- Steady-state enumeration is scoped to `pw-<projectId>`; launch-time recovery may inspect only the focused window (never `--all`).

## Token format
- `PW:<projectId>`
- Deterministic per project (one window per project).
- Used for both Chrome and VS Code window identification.

## Chrome (decided)
- Launch Chrome with a deterministic window name token.
  - Example: `open -na "Google Chrome" --args --new-window --window-name="PW:<projectId>" <urls...>`
  - If `project.chromeProfileDirectory` is set, include `--profile-directory="<dir>"` in the launch args.
- **Stage 1 (steady-state):** list only the target workspace, filtered by bundle id:
  - `aerospace list-windows --workspace pw-<projectId> --app-bundle-id com.google.Chrome --json --format '%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title} %{window-layout}'`
  - Match by token in `window-title`.
- Outcomes:
  - Exactly one match: use it.
  - Multiple matches: **WARN + choose lowest window id** (deterministic).
  - Zero matches: launch Chrome, then detect it.
- **Stage 2 (post-launch, workspace poll):**
  - Poll `list-windows --workspace pw-<projectId> --app-bundle-id com.google.Chrome ...` for the token.
  - Keep this probe short (≈0.5–0.8s), then move to focused capture.
- **Stage 3 (post-launch, focused recovery):**
  - Poll `aerospace list-windows --focused --json --format '%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title} %{window-layout}'`.
  - Accept only if:
    - `app-bundle-id == com.google.Chrome`
    - `window-title` contains the token.
  - Move the focused window into `pw-<projectId>`.
  - If nothing matches before timeout, fail loudly.

## IDE (VS Code + Antigravity)
- Set `window.title` in the generated `.code-workspace` file to include the token.
  - Example title: `PW:<projectId> - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}`
- Store workspace files under `~/.local/state/project-workspaces/vscode/<projectId>.code-workspace`.
- **Stage 1 (steady-state):** list only the target workspace, filtered by bundle id when known:
  - `aerospace list-windows --workspace pw-<projectId> --app-bundle-id <IDE_BUNDLE_ID> --json --format '%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title} %{window-layout}'`
  - Match by token in `window-title` + IDE identity (bundle id or app name).
- Outcomes:
  - Exactly one match: use it.
  - Multiple matches: **WARN + choose lowest window id** (deterministic).
  - Zero matches: launch IDE, then detect it.
- **Stage 2 (post-launch, workspace poll):**
  - Poll `list-windows --workspace pw-<projectId> --app-bundle-id <IDE_BUNDLE_ID> ...` for the token.
  - Keep this probe short (≈0.5–0.8s), then move to focused capture.
- **Stage 3 (post-launch, focused recovery):**
  - Poll `aerospace list-windows --focused --json --format '%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title} %{window-layout}'`.
  - Accept only if:
    - IDE identity matches (bundle id/app name)
    - `window-title` contains the token.
  - Move the focused window into `pw-<projectId>`.
  - If nothing matches before timeout, fail loudly.

## Validation requirements
- Verify the Chrome `--window-name` token appears in AeroSpace `list-windows --workspace pw-<projectId>` `window-title` output.
- Verify VS Code/Antigravity `window.title` tokens appear in AeroSpace `list-windows --workspace pw-<projectId>` output.
- If workspace polling fails after launch, verify focused-window recovery by inspecting `list-windows --focused` output.
