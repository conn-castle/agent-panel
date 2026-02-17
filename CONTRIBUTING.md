# Contributing to AgentPanel

Thanks for your interest in contributing. This guide covers everything you need to get started.

## Prerequisites

- macOS 15.7 or later (Apple Silicon)
- Xcode (full install, not just command-line tools)
- [Homebrew](https://brew.sh/)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [xcbeautify](https://github.com/cpisciotta/xcbeautify): `brew install xcbeautify`

## Architecture

AgentPanel is structured as four build targets:

| Target | Type | Role |
|--------|------|------|
| `AgentPanelApp` | Application | Menu bar UI, switcher panel, onboarding, hotkey registration |
| `AgentPanelCore` | Static framework | All business logic: config parsing, Doctor checks, project activation, layout engine, window management |
| `AgentPanelAppKit` | Static framework | System-level implementations (Accessibility APIs, NSScreen, CGDisplay) behind Core-defined protocols |
| `AgentPanelCLI` + `AgentPanelCLICore` | Tool + static framework | `ap` CLI entrypoint and command handling |

**Key design principles:**

- **Core owns business logic.** The app is a thin presentation layer. Core never imports AppKit.
- **Protocol-based dependency injection.** System interactions (AeroSpace CLI, window positioning, screen detection) are defined as protocols in Core with concrete implementations in AppKit. Tests use stub implementations.
- **`Result<T, ApCoreError>` pattern.** Errors are typed and carry category, message, detail, command, and exit code.
- **Fail loudly.** No silent fallbacks for missing or invalid configuration. Unknown config keys are hard failures.

## Getting Started

```sh
# Validate Xcode toolchain
scripts/dev_bootstrap.sh

# Generate Xcode project from project.yml
scripts/regenerate_xcodeproj.sh

# Build (Debug, no code signing)
scripts/build.sh

# Run tests with coverage gate (90% minimum)
scripts/test.sh
```

The Xcode project (`AgentPanel.xcodeproj`) is generated from `project.yml` using XcodeGen. If you add or rename source files, regenerate the project.

## Testing

Tests live in `AgentPanelCoreTests/` and `AgentPanelCLITests/`. Coverage is enforced at 90% minimum on `AgentPanelCore` and `AgentPanelCLICore`. The `AgentPanelAppKit` target is excluded from the coverage gate because it requires a live window server.

```sh
# Run all tests with coverage
scripts/test.sh

# Re-check coverage from existing results
scripts/coverage_gate.sh build/TestResults/Test-AgentPanel.xcresult
```

**Test conventions:**

- Use `@testable import AgentPanelCore` for Core tests.
- Tests must not launch real executables (`code`, `al`, `aerospace`). Use stub/mock implementations.
- Thread-safe test doubles are required for concurrent code paths (use `NSLock`).
- New test files require `scripts/regenerate_xcodeproj.sh` before Xcode discovers them.

## Adding New Files

1. Create the file in the appropriate source directory.
2. Add the file path to `project.yml` if it's in a new directory not already covered by the `sources` glob.
3. Run `scripts/regenerate_xcodeproj.sh`.
4. Verify with `scripts/build.sh`.

## Code Style

- Swift with strict typing. No force-unwrapping in production code.
- Public functions include docstrings describing arguments and return values.
- Follow existing patterns in the codebase. When in doubt, look at how similar code is structured.

## Git Hooks

Install the pre-commit hook (runs full test suite before commit):

```sh
scripts/install_git_hooks.sh
```

## Pull Requests

1. Fork the repository and create a feature branch.
2. Make your changes with tests.
3. Ensure `scripts/test.sh` passes (build + tests + coverage gate).
4. Open a pull request against `main`.
5. Describe what changed and why.

## Reporting Issues

Open a GitHub issue with:

- What you expected to happen.
- What actually happened.
- Output of `ap doctor` (if relevant).
- macOS version and AgentPanel version (`ap --version`).

## Internal Documentation

These files are maintained for development context and are not user-facing:

- `docs/CORE_API.md` -- public API reference for AgentPanelCore
- `docs/using_aerospace.md` -- AeroSpace CLI usage patterns
- `docs/agent-layer/` -- roadmap, decisions, issues, backlog, commands
