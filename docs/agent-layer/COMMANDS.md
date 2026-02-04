# Commands

Note: This is an agent-layer memory file. It is primarily for agent use.

## Purpose
Canonical, repeatable **development workflow** commands for this repository (setup, build, run, test, coverage, lint/format, typecheck, migrations, scripts). This file is not for application/CLI usage documentation.

## Format
- Prefer commands that are stable and will be used repeatedly. Avoid one-off debugging commands.
- Organize commands using headings that fit the repo. Create headings as needed.
- If the repo is a monorepo, group commands per workspace/package/service and specify the working directory.
- When commands change, update this file and remove stale entries.
- Insert entries (and any needed headings) below `<!-- ENTRIES START -->`.

### Entry template
````text
- <Short purpose>
```bash
<command>
```
Run from: <repo root or path>  
Prerequisites: <only if critical>  
Notes: <optional constraints or tips>
````

<!-- ENTRIES START -->

## Verify

Run the doctor verification suite (checks config, dependencies, permissions, and app state):

```bash
ap doctor
```

Run from repo root (or anywhere if installed).

## Generate

Regenerate `AgentPanel.xcodeproj` from `project.yml` (XcodeGen):

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

Run from repo root. Prerequisites: `xcbeautify` installed (`brew install xcbeautify`). This script runs `scripts/dev_bootstrap.sh` and then uses `xcodebuild` with a repo-owned DerivedData path under `build/DerivedData`.

Reference (underlying `xcodebuild`):

```bash
xcodebuild -project AgentPanel.xcodeproj -scheme AgentPanel -derivedDataPath build/DerivedData -resolvePackageDependencies
xcodebuild -project AgentPanel.xcodeproj -scheme AgentPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO
```

## Clean

Clean build artifacts (DerivedData + build output). Logs are outside the repo and must be removed manually as instructed by the script:

```bash
scripts/clean.sh
```

Run from repo root. Notes: The script prints the exact `rm -rf` command to delete logs under `~/.local/state/agent-panel/logs`.

## Test

Run unit tests (Debug), without code signing:

```bash
scripts/test.sh
```

Run from repo root. Prerequisites: `xcbeautify` installed (`brew install xcbeautify`). This script runs `scripts/dev_bootstrap.sh` and then uses `xcodebuild` with a repo-owned DerivedData path under `build/DerivedData`.

Reference (underlying `xcodebuild`):

```bash
xcodebuild -project AgentPanel.xcodeproj -scheme AgentPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData test CODE_SIGNING_ALLOWED=NO
```
