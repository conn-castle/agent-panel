# Project Windows

## Principles
- CLI-only: AeroSpace CLI is the sole source of truth (no AX/geometry checks).
- Binding-based: only bound windows are moved/resized; unbound windows are untouched.
- Read-only global snapshot: `list-windows --all --json` is used to resolve/prune bindings.
- Auto-open: if a role has no binding after pruning, activation opens a new window and binds it (one per role).
- Conditional layout: canonical layout applies only when the workspace is newly opened (no bound windows present).

## Required windows
Each project maintains **one bound IDE window** and **one bound Chrome window**.
- If bindings are missing or stale, activation opens a new window and binds it.
- Activation fails only if workspace focus cannot be confirmed or a required window cannot be opened/detected.

## Commands used
- `summon-workspace <workspace>`
- `list-workspaces --focused --format "%{workspace}"`
- `list-windows --all --json --format '%{window-id} %{workspace} %{app-bundle-id} %{app-name} %{window-title} %{window-layout} %{monitor-appkit-nsscreen-screens-id}'`
- `move-node-to-workspace --window-id <id> <workspace>`
- `focus --window-id <id>`
- `flatten-workspace-tree --workspace <workspace>` (only on newly opened workspace)
- `balance-sizes --workspace <workspace>` (only on newly opened workspace)
- `layout --window-id <ideId> h_tiles` (only on newly opened workspace)
- `resize --window-id <ideId> width <points>` (only on newly opened workspace)

## Monitor index
AeroSpace returns `monitor-appkit-nsscreen-screens-id` in `list-windows` output. This is a 1-based index into `NSScreen.screens` and is used to compute the focused monitor's visible width for deterministic resizing.

## Validation checklist
- Bound windows move into the project workspace; unbound windows never move.
- If bindings are missing, activation opens and binds one IDE + one Chrome window.
- Layout is applied only when the workspace had no bound windows present.
- Workspace focus is confirmed via `list-workspaces --focused` after switch and after move.
