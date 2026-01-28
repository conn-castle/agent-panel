# Project Windows

## Principles
- No guessing. Only act on windows that are deterministically identified as ProjectWorkspaces-owned.
- No fallbacks. If a window cannot be identified with certainty, fail loudly.
- Cross-workspace scanning is allowed **only** when matching a ProjectWorkspaces-owned token.

## Token format
- `PW:<projectId>`
- Deterministic per project (one window per project).
- Used for both Chrome and VS Code window identification.

## Chrome (decided)
- Launch Chrome with a deterministic window name token.
  - Example: `open -na "Google Chrome" --args --new-window --window-name="PW:<projectId>" <urls...>`
  - If `project.chromeProfileDirectory` is set, include `--profile-directory="<dir>"` in the launch args.
- Scan all windows via AeroSpace and match **exactly**:
  - `appBundleId == com.google.Chrome`
  - `window-title` contains the token followed by a non-word character or end of string.
- Outcomes:
  - Exactly one match: ensure it is in `pw-<projectId>` (move if needed).
  - Zero matches: create a new Chrome window with the token, then detect/move it.
  - Multiple matches: fail (ambiguous).

## IDE (VS Code + Antigravity)
- Set `window.title` in the generated `.code-workspace` file to include the token.
  - Example title: `PW:<projectId> - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}`
- Store workspace files under `~/.local/state/project-workspaces/vscode/<projectId>.code-workspace`.
- Scan all windows via AeroSpace and match **exactly**:
  - IDE identity (bundle id or app name).
  - `window-title` contains the token followed by a non-word character or end of string.
- Outcomes:
  - Exactly one match: ensure it is in `pw-<projectId>` (move if needed).
  - Zero matches after launch timeout: fail.
  - Multiple matches: fail (ambiguous).

## Validation requirements
- Verify the Chrome `--window-name` token appears in AeroSpace `list-windows --all` `window-title` output.
- Verify VS Code/Antigravity `window.title` tokens appear in AeroSpace `list-windows --all` output.
