# Commands

Purpose: Canonical, repeatable commands for this repository.

Notes for updates:
- Add commands that are expected to be used repeatedly (setup, development server, build, lint, format, typecheck, tests, coverage, database migrations, common scripts).
- Include purpose, command, where to run it, and prerequisites.
- Keep entries concise and deduplicated.
- Do not add one-off debugging commands.

<!-- ENTRIES START -->

## Generate

Regenerate `ProjectWorkspaces.xcodeproj` from `project.yml` (XcodeGen):

```bash
scripts/regenerate_xcodeproj.sh
```

Run from repo root. Prerequisites: `xcodegen` installed (for example via `brew install xcodegen`).

## Bootstrap

Validate Xcode toolchain selection and first-launch state:

```bash
scripts/dev_bootstrap.sh
```

Run from repo root. Prerequisites: full Xcode installed and selected via `xcode-select`.
If this fails due to first-launch state, run the printed fix commands (for example `sudo xcodebuild -runFirstLaunch`).

## Build

Build the app + CLI (Debug), without code signing:

```bash
scripts/build.sh
```

Run from repo root. This script runs `scripts/dev_bootstrap.sh` and then uses `xcodebuild` with a repo-owned DerivedData path under `.agent-layer/tmp`.

Reference (underlying `xcodebuild`):

```bash
xcodebuild -project ProjectWorkspaces.xcodeproj -scheme ProjectWorkspaces -derivedDataPath .agent-layer/tmp/DerivedData -resolvePackageDependencies
xcodebuild -project ProjectWorkspaces.xcodeproj -scheme ProjectWorkspaces -configuration Debug -destination 'platform=macOS' -derivedDataPath .agent-layer/tmp/DerivedData build CODE_SIGNING_ALLOWED=NO
```

## Test

Run unit tests (Debug), without code signing:

```bash
scripts/test.sh
```

Run from repo root. This script runs `scripts/dev_bootstrap.sh` and then uses `xcodebuild` with a repo-owned DerivedData path under `.agent-layer/tmp`.

Reference (underlying `xcodebuild`):

```bash
xcodebuild -project ProjectWorkspaces.xcodeproj -scheme ProjectWorkspaces -configuration Debug -destination 'platform=macOS' -derivedDataPath .agent-layer/tmp/DerivedData test CODE_SIGNING_ALLOWED=NO
```
