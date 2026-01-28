# Backlog

Note: This is an agent-layer memory file. It is primarily for agent use.

## Features and tasks (not scheduled)

<!-- ENTRIES START -->

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

- Backlog 2026-01-27 a9f2b8: Show loader during project startup
    Priority: Medium. Area: UI/UX
    Description: Display a loading indicator or progress status while project workspaces and browsers are being launched.
    Acceptance criteria: User sees a clear visual indication that the system is working during the startup process, especially while waiting for Chrome.
    Notes: Chrome's first launch is noted as being particularly slow.
