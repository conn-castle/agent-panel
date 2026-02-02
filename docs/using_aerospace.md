## Efficient window listing with the `aerospace` CLI

### Avoid `--all` unless you truly need it

`aerospace list-windows --all` is an alias for `--monitor all`, and the docs explicitly say to use it with caution; for multi‑monitor setups they recommend `--monitor focused` in almost all cases. ([Nikita Bobko][1])

So, yes: `--all` can be noticeably slow (or just feel slow) because it’s the maximum scope and can generate a lot of output.

---

## Scope first (fast), then filter

`list-windows` is built around narrowing by **workspace** and/or **monitor**, then optionally filtering by app:

### 1) Smallest scope: one window

```sh
aerospace list-windows --focused
```

([Nikita Bobko][1])

### 2) Typical: current workspace

```sh
aerospace list-windows --workspace focused
```

`focused` is a special workspace name. ([Nikita Bobko][1])

### 3) “What’s on screen right now?” (all visible workspaces)

```sh
aerospace list-windows --workspace visible
```

`visible` represents all currently visible workspaces (important on multi‑monitor). ([Nikita Bobko][1])

### 4) Focused monitor only (preferred instead of `--all` on multi-monitor)

```sh
aerospace list-windows --monitor focused
```

Monitor selectors can be numeric (left→right), or special IDs like `focused`, `mouse`, `all`. ([Nikita Bobko][1])

### 5) Visible windows on the focused monitor (common “local” query)

```sh
aerospace list-windows --monitor focused --workspace visible
```

This combines both scopers (allowed by the command signature). ([Nikita Bobko][1])

---

## Filter at the source (don’t post-filter huge output)

If you only care about a specific app:

### Filter by bundle ID

```sh
aerospace list-windows --workspace visible --app-bundle-id com.google.Chrome
```

([Nikita Bobko][1])

### Filter by PID

```sh
aerospace list-windows --workspace visible --pid 12345
```

([Nikita Bobko][1])

To discover app bundle IDs/PIDs for running GUI apps:

```sh
aerospace list-apps
```

([Nikita Bobko][1])

---

## Reduce output (often the real speed win)

By default, `list-windows` prints window id + app name + window title. ([Nikita Bobko][1])
If you’re going to feed results into another command/script, you usually only need IDs:

```sh
aerospace list-windows --workspace visible --format '%{window-id}'
```

([Nikita Bobko][1])

Other useful output modes:

### Count only

```sh
aerospace list-windows --workspace visible --count
```

([Nikita Bobko][1])

### JSON (for scripts)

```sh
aerospace list-windows --workspace visible --json
```

([Nikita Bobko][1])

If you use JSON, a safe approach is to inspect keys first:

```sh
aerospace list-windows --workspace visible --json | jq '.[0] | keys'
```

---

## If `--all` is *unusually* slow or returns “ghost” entries

`--all` being slower than scoped queries is expected (it’s global scope, and discouraged for casual use). ([Nikita Bobko][1])
If it’s pathologically slow or you suspect incorrect window state, AeroSpace provides an interactive debugging command intended for bug reports about incorrect window handling:

```sh
aerospace debug-windows
```

([Nikita Bobko][1])

---

# Ways to use AeroSpace on macOS

## 1) Keybindings + config (`~/.aerospace.toml`)

AeroSpace searches for config in:

* `~/.aerospace.toml`
* or `${XDG_CONFIG_HOME}/aerospace/aerospace.toml` (defaults to `~/.config` if `XDG_CONFIG_HOME` is unset) ([Nikita Bobko][2])

The guide states there are two main ways to use AeroSpace commands:

1. bind keys in the config
2. run commands in the CLI ([Nikita Bobko][2])

## 2) CLI for ad‑hoc control + scripting

Manual install notes that putting `bin/aerospace` on your `PATH` is optional, and specifically needed if you want to interact via CLI. ([Nikita Bobko][2])

Common uses:

* scripts that query state (`list-windows`, `list-workspaces`, `list-monitors`)
* integration with `jq`, `fzf`, status bars, launchers, etc.

## 3) Event-driven automation (callbacks)

The guide documents callbacks such as:

* `on-window-detected`
* `on-focus-changed` / `on-focused-monitor-changed`
* `exec-on-workspace-change` ([Nikita Bobko][2])

These are the usual mechanism for “auto-assign app X to workspace Y,” “mouse follows focus,” and triggering external tools when workspaces change.

## 4) Third-party integrations / UX enhancements

The official “Goodies” page lists integrations and workflow ideas, including:

* a third‑party Raycast extension
* trackpad gesture workflows for switching workspaces
* showing workspaces in Sketchybar or simple-bar
* highlighting focused windows via JankyBorders
* AppleScript snippets for opening new windows without pulling an existing workspace into focus ([Nikita Bobko][3])

---

## Practical default recommendation

If your habit is `list-windows --all`, switch to:

1. `--focused` (single window)
2. `--workspace focused` (current workspace)
3. `--workspace visible` (everything you can currently see)
4. `--monitor focused` (current monitor only)

Then add `--app-bundle-id` / `--pid`, and use `--format` to output only what you need. This matches the project’s own guidance to prefer `--monitor focused` over global queries in multi-monitor setups. ([Nikita Bobko][1])

[1]: https://nikitabobko.github.io/AeroSpace/commands "AeroSpace Commands"
[2]: https://nikitabobko.github.io/AeroSpace/guide "AeroSpace Guide"
[3]: https://nikitabobko.github.io/AeroSpace/goodies "AeroSpace Goodies"
