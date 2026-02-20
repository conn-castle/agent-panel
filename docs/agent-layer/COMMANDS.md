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
make regen
```

Run from repo root. Prerequisites: `xcodegen` installed (for example via `brew install xcodegen`).

Reference (underlying script): `scripts/regenerate_xcodeproj.sh`

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
make build
```

Run from repo root. Prerequisites: `xcbeautify` installed (`brew install xcbeautify`).

Reference (underlying script): `scripts/build.sh`. Runs `scripts/dev_bootstrap.sh` and then uses `xcodebuild` with a repo-owned DerivedData path under `build/DerivedData`.

## Clean

Clean build artifacts (DerivedData + build output). Logs are outside the repo and must be removed manually as instructed by the script:

```bash
make clean
```

Run from repo root. Notes: The script prints the exact `rm -rf` command to delete logs under `~/.local/state/agent-panel/logs`.

Reference (underlying script): `scripts/clean.sh`

## Test (fast, no coverage)

Run unit tests (Debug) without code coverage for fast local iteration:

```bash
make test
```

Run from repo root. Prerequisites: `xcbeautify` installed (`brew install xcbeautify`).
Notes: Skips coverage instrumentation and the coverage gate. Use `make coverage` for the full quality gate.

Reference (underlying script): `scripts/test.sh --no-coverage`

## Test with Coverage (quality gate)

Run unit tests with code coverage enabled, enforce the 90% coverage gate, and print a per-file coverage summary:

```bash
make coverage
```

Run from repo root. Prerequisites: `xcbeautify` installed (`brew install xcbeautify`).
Notes: This is the quality gate used by CI and the pre-commit hook. Prints per-file coverage sorted by % ascending (lowest first).

Reference (underlying script): `scripts/test.sh` (default, with coverage)

## Re-check Coverage Gate

Re-check the coverage gate from an existing test result bundle:

```bash
scripts/coverage_gate.sh build/TestResults/Test-AgentPanel.xcresult
```

Run from repo root. Notes: the `.xcresult` bundle is produced by `make coverage`.

## Coverage Gate Integration Test

Run integration tests for `coverage_gate.swift` (verifies per-file output, sorting, pass/fail logic):

```bash
make test-coverage-gate
```

Run from repo root. Notes: fast — pipes JSON fixtures to `coverage_gate.swift`, no xcodebuild.

Reference (underlying script): `scripts/test_coverage_gate.sh`

## Release Preflight

Validate release-readiness (version format, Info.plist variables, entitlements, CI scripts, workflow config):

```bash
make preflight
```

Run from repo root. Notes: runs automatically in CI on every push/PR. Also useful locally before tagging a release.

Reference (underlying script): `scripts/ci_preflight.sh`

## Release (CI only)

The release workflow (`.github/workflows/release.yml`) runs on tag push (`v*`). These scripts are called by CI and are not intended for local use:

- `scripts/ci_preflight.sh` — validate release configuration (also runs in CI workflow)
- `scripts/ci_setup_signing.sh` — import certs into temp keychain
- `scripts/ci_archive.sh` — archive + codesign app and CLI with Developer ID
- `scripts/ci_package.sh` — create DMG, PKG, tarball
- `scripts/ci_notarize.sh <artifact>` — notarize + staple a single artifact
- `scripts/ci_release_validate.sh` — validate all artifacts post-notarization

To create a release:

```bash
git tag vX.Y.Z && git push origin main vX.Y.Z
```

Run from repo root. Prerequisites: GitHub `release` environment with secrets (`APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_PRIVATE_KEY_B64`, `DEVELOPER_ID_APP_P12_B64`, `DEVELOPER_ID_APP_P12_PASSWORD`, `DEVELOPER_ID_INSTALLER_P12_B64`, `DEVELOPER_ID_INSTALLER_P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `DEVELOPER_ID_APP_IDENTITY`, `DEVELOPER_ID_INSTALLER_IDENTITY`) and variables (`CLI_INSTALL_PATH`).

## Git hooks

Install repo-managed git hooks (pre-commit runs `make coverage`):

```bash
make hooks
```

Run from repo root. Notes: sets local git config `core.hooksPath` to `.githooks`.

Reference (underlying script): `scripts/install_git_hooks.sh`
