# Issues

Note: This is an agent-layer memory file. It is primarily for agent use.

## Open issues

<!-- ENTRIES START -->

- Issue 2026-01-26 1dad6f1: Doctor.swift complexity growing
    Priority: Low. Area: Maintainability
    Description: Doctor.swift has grown to approximately 1200 lines with mixed check responsibilities (AeroSpace, config, apps, accessibility, hotkey).
    Next step: Consider extracting focused checker structs (AeroSpaceChecker, AppDiscoveryChecker, ConfigChecker) before Phase 3 adds more checks.
