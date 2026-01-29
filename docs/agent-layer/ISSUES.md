# Issues

Note: This is an agent-layer memory file. It is primarily for agent use.

## Open issues

<!-- ENTRIES START -->

- Issue 2026-01-28 d1u8pl: Duplicate launch detection logic in Core
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: ActivationService.swift and ChromeLauncher.swift contain identical LaunchDetectionTimeouts structs and calculation logic to split the polling budget.
    Next Step: Extract this logic to a shared internal helper (e.g., LaunchDetectionStrategy) within ProjectWorkspacesCore.
    Notes: DRY violation that increases maintenance burden.

- Issue 2026-01-28 b7v1s3: Brittle switcher visibility check
    Priority: Low. Area: ProjectWorkspacesApp
    Description: SwitcherPanelController.scheduleVisibilityCheck uses a hardcoded 0.15s delay to verify panel visibility, which is brittle on loaded systems and may cause false positive logs.
    Next Step: Replace the fixed delay with event-based observation (e.g., NSWindow.didBecomeKeyNotification) or document the limitation.
    Notes: Currently affects diagnostics only, not user functionality.

- Issue 2026-01-28 106746f: Duplicate retry policy logic in ActivationService and ChromeLauncher
    Priority: Medium. Area: ProjectWorkspacesCore
    Description: shouldRetryPoll and shouldRetryFocusedWindow methods are duplicated with identical logic in both ActivationService.swift and ChromeLauncher.swift.
    Next Step: Extract as AeroSpaceCommandError extension or shared utility as part of LaunchDetectionStrategy refactor.
    Notes: Can be addressed together with issue d1u8pl.
