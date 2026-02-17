# Releasing AgentPanel

This document covers how to create a new release. Releases are built, signed, notarized, and published automatically by CI when a version tag is pushed.

## Prerequisites

The GitHub repository must have a `release` environment configured with the following secrets and variables. See `human_setup.md` (not tracked in git) for the one-time setup process.

### Secrets (in `release` environment)

| Secret | Description |
|--------|-------------|
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer ID |
| `APPLE_API_PRIVATE_KEY_B64` | Base64-encoded `.p8` API key |
| `DEVELOPER_ID_APP_P12_B64` | Base64-encoded Developer ID Application `.p12` |
| `DEVELOPER_ID_APP_P12_PASSWORD` | Password for the Application `.p12` |
| `DEVELOPER_ID_INSTALLER_P12_B64` | Base64-encoded Developer ID Installer `.p12` |
| `DEVELOPER_ID_INSTALLER_P12_PASSWORD` | Password for the Installer `.p12` |
| `KEYCHAIN_PASSWORD` | Random password for CI temporary keychain |
| `DEVELOPER_ID_APP_IDENTITY` | Full identity string (e.g., `Developer ID Application: Name (TEAMID)`) |
| `DEVELOPER_ID_INSTALLER_IDENTITY` | Full identity string (e.g., `Developer ID Installer: Name (TEAMID)`) |

### Variables (in `release` environment)

| Variable | Value |
|----------|-------|
| `MACOS_DEPLOYMENT_TARGET` | `16.0` |
| `CLI_INSTALL_PATH` | `/usr/local/bin/ap` |
| `RELEASE_TAG_PREFIX` | `v` |

## Creating a Release

### 1. Bump the version

Update `MARKETING_VERSION` in `project.yml`:

```yaml
MARKETING_VERSION: "0.2.0"
```

Regenerate the Xcode project and verify:

```sh
scripts/regenerate_xcodeproj.sh
scripts/build.sh
scripts/test.sh
```

### 2. Update the changelog

Add a new section to `CHANGELOG.md` with the version and date:

```markdown
## [0.2.0] - 2026-03-01

### Added
- ...

### Fixed
- ...
```

### 3. Commit, tag, and push

```sh
git add project.yml AgentPanel.xcodeproj CHANGELOG.md
git commit -m "Bump version to 0.2.0"
git tag v0.2.0
git push origin main v0.2.0
```

The tag push triggers the release workflow.

### 4. Monitor the workflow

The release workflow (`.github/workflows/release.yml`) runs on `macos-15` and:

1. Validates the tag version matches `MARKETING_VERSION` in `project.yml`.
2. Installs build dependencies (xcbeautify, xcodegen, create-dmg).
3. Generates the Xcode project.
4. Runs build and tests (full test suite with coverage gate).
5. Imports signing certificates into a temporary keychain.
6. Archives the app and exports with Developer ID signing.
7. Codesigns the CLI binary with hardened runtime.
8. Creates distribution artifacts:
   - `AgentPanel-v<version>-macos-arm64.dmg` (app)
   - `ap-v<version>-macos-arm64.pkg` (CLI installer, signed with Installer cert)
   - `ap-v<version>-macos-arm64.tar.gz` (CLI binary)
9. Notarizes the DMG and PKG with Apple.
10. Validates all artifacts (mounts DMG, verifies signatures, checks notarization).
11. Generates `SHA256SUMS`.
12. Creates a GitHub Release with all artifacts attached.

### 5. Verify the release

After the workflow completes:

```sh
# Download and verify the DMG
spctl --assess --verbose=4 --type execute /path/to/AgentPanel.app

# Verify the PKG
pkgutil --check-signature /path/to/ap-v0.2.0-macos-arm64.pkg

# Verify the tarball CLI
xattr -d com.apple.quarantine /path/to/ap
./ap --version
```

## CI Scripts

These scripts are called by the release workflow and are not intended for local use:

| Script | Purpose |
|--------|---------|
| `scripts/ci_setup_signing.sh` | Import certificates into temporary keychain |
| `scripts/ci_archive.sh` | Archive, export, and codesign CLI |
| `scripts/ci_package.sh` | Create DMG, PKG, and tarball |
| `scripts/ci_notarize.sh` | Notarize and staple a single artifact |
| `scripts/ci_release_validate.sh` | Validate all artifact signatures and notarization |

## Troubleshooting

**Tag version mismatch:** The workflow validates that the tag version (e.g., `v0.2.0` -> `0.2.0`) matches `MARKETING_VERSION` in `project.yml`. If they don't match, the workflow fails immediately.

**Notarization fails:** Check the Apple Developer portal for notarization logs. Common issues: missing entitlements, unsigned nested binaries, or expired certificates.

**`codesign` cannot find identity:** Verify the `.p12` password is correct and the identity string in `DEVELOPER_ID_APP_IDENTITY` matches the certificate exactly (including team ID in parentheses).
