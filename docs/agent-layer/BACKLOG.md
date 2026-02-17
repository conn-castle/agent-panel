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

- Backlog 2026-02-16 chrome-profile-selection: Enable chromeProfile selection in config
    Priority: Medium. Area: Core/Chrome
    Description: Implement support for selecting specific Chrome profiles via the configuration file (config.toml). This allows different projects to open in their respective Chrome profiles, maintaining separation of state and accounts.
    Acceptance criteria: Chrome windows for a project open using the profile specified in the project's configuration.
    Notes: May involve using `--profile-directory` or similar Chrome CLI flags.

- Backlog 2026-02-16 chrome-auto-assoc: Auto-associate existing Chrome window in project workspace
    Priority: Medium. Area: Core/Chrome
    Description: If a project lacks an associated Chrome window but a window is found within the project's workspace (e.g., without matching title), associate it instead of opening a new one.
    Acceptance criteria: Selecting a project without a matched Chrome window automatically adopts an existing Chrome window if it's already on the project's assigned workspace/screen.
    Notes: Improves seamlessness when switching projects where Chrome windows might have lost their specific title match but are still in the right place.

- Backlog 2026-02-16 homebrew-dist: Homebrew packaging for app + CLI
    Priority: Low. Area: Release
    Description: Provide optional Homebrew distribution (cask/formula or unified strategy) on top of GitHub tagged release assets.
    Acceptance criteria: A documented Homebrew install/upgrade path exists and is validated against release artifacts.
    Notes: Deferred intentionally while release work focuses on signed + notarized arm64 GitHub tagged releases.

- Backlog 2026-02-15 window-cycling-ui: UI overlay for project window cycling (Option-Tab)
    Priority: Medium. Area: App/UX
    Description: Add a UI overlay for project-scoped window cycling (Option-Tab) that shows the available windows, similar to the macOS Command-Tab switcher. This provides visual feedback and allows for easier navigation between multiple windows within a project workspace.
    Acceptance criteria: Pressing and holding Option while Tabbing displays a UI panel with window icons/titles; releasing Option selects the highlighted window.

- Backlog 2026-02-14 chromecolor: Chrome visual differentiation matching VS Code project color
    Priority: Low. Area: Core/Chrome
    Description: Apply project color to the Chrome window to visually match the associated VS Code window. Possible approaches: Chrome profile customization, theme injection, or Chrome extension.
    Acceptance criteria: Chrome window for a project visually reflects the project's configured color.
    Notes: Deferred from Phase 7. Chrome has no clean programmatic injection point for color theming (unlike VS Code's Peacock extension). May require a custom Chrome extension or Chrome profile switching.

- Backlog 2026-02-09 trackpad-hotcorners: Hot Corners and Trackpad activation/switching
    Priority: Medium. Area: App/UX
    Description: Add support for Hot Corners and trackpad gestures (e.g., specific swipes) to trigger the project switcher or quickly toggle between recent projects. This aims to streamline navigation for laptop users who may prefer gesture-based interaction over keyboard shortcuts.
    Acceptance criteria: User can configure a specific screen corner or trackpad gesture in the settings to invoke the AgentPanel switcher.
