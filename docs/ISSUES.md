# Issues

Purpose: Deferred defects, maintainability refactors, technical debt, risks, and engineering concerns.

Notes for updates:
- Add an entry only when you are not fixing it now.
- Keep each entry 3 to 5 lines (the first line plus 2 to 4 indented lines).
- Lines 2 to 5 must be indented by 4 spaces so they stay associated with the entry.
- Prevent duplicates by searching and merging.
- Remove entries when fixed.

Entry format:
- Issue YYYY-MM-DD abcdef: Short title
    Priority: Critical, High, Medium, or Low. Area: <area>
    Description: <observed problem or risk>
    Next step: <smallest concrete next action>
    Notes: <optional dependencies or constraints>

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
