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
This script also enforces the repo coverage gate via `scripts/coverage_gate.sh`.

Reference (underlying `xcodebuild`):

```bash
xcodebuild -project AgentPanel.xcodeproj -scheme AgentPanel -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData -resultBundlePath build/TestResults/Test-AgentPanel.xcresult -enableCodeCoverage YES test CODE_SIGNING_ALLOWED=NO
```

## Coverage

Re-check the coverage gate from an existing test result bundle:

```bash
scripts/coverage_gate.sh build/TestResults/Test-AgentPanel.xcresult
```

Run from repo root. Notes: the `.xcresult` bundle is produced by `scripts/test.sh`.

## Release Preflight

Validate release-readiness (version format, Info.plist variables, entitlements, CI scripts, workflow config):

```bash
scripts/ci_preflight.sh
```

Run from repo root. Notes: runs automatically in CI on every push/PR. Also useful locally before tagging a release.

## Release (CI only)

The release workflow (`.github/workflows/release.yml`) runs on tag push (`v*`). These scripts are called by CI and are not intended for local use:

- `scripts/ci_preflight.sh` — validate release configuration (also runs in CI workflow)
- `scripts/ci_setup_signing.sh` — import certs into temp keychain
- `scripts/ci_archive.sh` — archive + export + CLI codesign
- `scripts/ci_package.sh` — create DMG, PKG, tarball
- `scripts/ci_notarize.sh <artifact>` — notarize + staple a single artifact
- `scripts/ci_release_validate.sh` — validate all artifacts post-notarization

To create a release:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

Run from repo root. Prerequisites: GitHub `release` environment with secrets (`APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_PRIVATE_KEY_B64`, `DEVELOPER_ID_APP_P12_B64`, `DEVELOPER_ID_APP_P12_PASSWORD`, `DEVELOPER_ID_INSTALLER_P12_B64`, `DEVELOPER_ID_INSTALLER_P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `DEVELOPER_ID_APP_IDENTITY`, `DEVELOPER_ID_INSTALLER_IDENTITY`) and variables (`CLI_INSTALL_PATH`, `RELEASE_TAG_PREFIX`).

## Git hooks

Install repo-managed git hooks (pre-commit runs `scripts/test.sh`):

```bash
scripts/install_git_hooks.sh
```

Run from repo root. Notes: sets local git config `core.hooksPath` to `.githooks`.
