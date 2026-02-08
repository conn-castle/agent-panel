# Backlog

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
Unscheduled user-visible features and tasks (distinct from issues; not refactors). Maintainability refactors belong in ISSUES.md.

## Format
- Insert new entries immediately below `<!-- ENTRIES START -->` (most recent first).
- Keep each entry **3–5 lines**.
- Line 1 starts with `- Backlog YYYY-MM-DD <id>:` and a short title.
- Lines 2–5 are indented by **4 spaces** and use `Key: Value`.
- Keep **exactly one blank line** between entries.
- Prevent duplicates: search the file and merge/rewrite instead of adding near-duplicates.
- When scheduled into ROADMAP.md, move the work into ROADMAP.md and remove it from this file.
- When implemented, remove the entry from this file.

### Entry template
```text
- Backlog YYYY-MM-DD abcdef: Short title
    Priority: Critical | High | Medium | Low. Area: <area>
    Description: <what the user should be able to do>
    Acceptance criteria: <clear condition to consider it done>
    Notes: <optional dependencies/constraints>
```

## Features and tasks (not scheduled)

<!-- ENTRIES START -->

- Backlog 2026-02-06 c2d3e4: Persist and restore project Chrome tabs
    Priority: Medium. Area: Browser Integration / Persistence
    Description: Track Chrome tabs opened during a project session and allow the project to automatically reopen all associated tabs upon activation.
    Acceptance criteria: Project activation restores the set of Chrome tabs from the previous session; tab URLs are persisted across app restarts.
    Notes: May require Chrome remote debugging or AppleScript integration.

- Backlog 2026-02-05 e2c1b4: Automatic Doctor run on operational errors
    Priority: Medium. Area: Diagnostics
    Description: Automatically trigger a `doctor` run when an error occurs during normal operation (e.g., project startup failure, command error).
    Acceptance criteria: When an error is encountered in the app's workflow, `Doctor` runs in the background or surfaces a diagnostic report to the user automatically.

- Backlog 2026-02-05 d1f2a3: Option to hide AeroSpace menu bar icon
    Priority: Medium. Area: macOS Integration
    Description: Provide a way to hide the AeroSpace icon from the macOS menu bar to reduce menu bar clutter.
    Acceptance criteria: A configuration setting or command successfully hides the AeroSpace icon while keeping its window management features active.
    Notes: Requires investigation into AeroSpace's ability to run in a "headless" or hidden-icon mode.

- Backlog 2026-01-28 c4e1a7: Switcher can add projects when config is missing
    Priority: Medium. Area: Switcher UX
    Description: Allow the switcher to open even without config.toml and provide an “Open Project...” picker that adds the project to config and then activates it.
    Acceptance criteria: With no config.toml, Open Switcher shows an “Open Project...” action, selecting a folder adds it to config and opens the project, and failures are reported clearly.
    Notes: Should preserve existing config ordering rules and avoid silent defaults; may require CLI-independent config writer.

- Backlog 2026-01-27 7d2f4a: Open project workspaces on dedicated macOS Spaces
    Priority: Medium. Area: macOS Integration
    Description: Ensure project workspaces are opened on dedicated macOS Spaces (either one space per workspace or all workspaces on a single dedicated space).
    Acceptance criteria: Workspaces reliably open on the intended macOS Space(s) as configured.
    Notes: User is undecided between one space per workspace vs. all on one space. Integration might involve AeroSpace.

- Backlog 2026-01-27 b4a1c3: Color code Chrome to match VS Code window
    Priority: Medium. Area: UI/UX Integration
    Description: Explore ways to automatically color code Chrome windows or profiles to match the theme or color palette of the associated VS Code workspace.
    Acceptance criteria: Chrome windows for a project have a visual indicator (like a theme or profile color) that matches the VS Code window color.
    Notes: May require Chrome profile customization or theme injection. VSCodeColorPalette.swift might be a reference.

