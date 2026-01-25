# Issues

Note: This is an agent-layer memory file. It is primarily for agent use.

## Open issues

<!-- ENTRIES START -->

- Issue 2026-01-13 9e1f4b2: Remove dependency on system temp directory for Xcode DerivedData
    Priority: Medium. Area: Build Infrastructure
    Description: Xcode builds are configured to use the system temporary directory for DerivedData, which is non-persistent and can lead to inefficient rebuilds or conflicts.
    Next step: Reconfigure project and scripts to use a stable, dedicated build directory outside of system temp.

- Issue 2026-01-13 832a05f: Replace deprecated name lookup in application discovery
    Priority: Low. Area: Maintainability
    Description: Application discovery uses a deprecated name lookup method when the bundle identifier is missing.
    Next step: Replace with a supported Launch Services lookup or documented alternative.
