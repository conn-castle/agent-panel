# Commands

Note: This is an agent-layer memory file. It is primarily for agent use.

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

Run from repo root. This script runs `scripts/dev_bootstrap.sh` and then uses `xcodebuild` with a repo-owned DerivedData path under `build/DerivedData`.

Reference (underlying `xcodebuild`):

```bash
xcodebuild -project ProjectWorkspaces.xcodeproj -scheme ProjectWorkspaces -derivedDataPath build/DerivedData -resolvePackageDependencies
xcodebuild -project ProjectWorkspaces.xcodeproj -scheme ProjectWorkspaces -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO
```

## Test

Run unit tests (Debug), without code signing:

```bash
scripts/test.sh
```

Run from repo root. This script runs `scripts/dev_bootstrap.sh` and then uses `xcodebuild` with a repo-owned DerivedData path under `build/DerivedData`.

Reference (underlying `xcodebuild`):

```bash
xcodebuild -project ProjectWorkspaces.xcodeproj -scheme ProjectWorkspaces -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData test CODE_SIGNING_ALLOWED=NO
```
