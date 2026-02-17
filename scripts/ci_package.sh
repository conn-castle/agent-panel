#!/usr/bin/env bash
set -euo pipefail

# Package staged artifacts into DMG, PKG, and tarball for distribution.
#
# Required environment variables:
#   DEVELOPER_ID_APP_IDENTITY       — for DMG codesigning
#   DEVELOPER_ID_INSTALLER_IDENTITY — for PKG signing
#   VERSION                         — e.g. "0.1.0"
#   CLI_INSTALL_PATH                — e.g. "/usr/local/bin/ap"
#   RUNNER_TEMP

staging_path="$RUNNER_TEMP/staging"
artifacts_path="$RUNNER_TEMP/artifacts"

mkdir -p "$artifacts_path"

# --- Validate inputs ---
if [[ ! -d "$staging_path/AgentPanel.app" ]]; then
  echo "error: staged app not found at $staging_path/AgentPanel.app" >&2
  exit 1
fi
if [[ ! -x "$staging_path/ap" ]]; then
  echo "error: staged CLI binary not found at $staging_path/ap" >&2
  exit 1
fi
if [[ -z "${CLI_INSTALL_PATH:-}" ]]; then
  echo "error: CLI_INSTALL_PATH is not set or empty" >&2
  exit 1
fi
if [[ "$CLI_INSTALL_PATH" != /* ]]; then
  echo "error: CLI_INSTALL_PATH must be an absolute path, got: $CLI_INSTALL_PATH" >&2
  exit 1
fi

# --- DMG ---
dmg_name="AgentPanel-v${VERSION}-macos-arm64.dmg"
echo "Creating DMG: $dmg_name"

# create-dmg expects a source directory; it copies the directory's contents into the DMG.
# Stage the .app inside a temp directory so the DMG root contains AgentPanel.app.
dmg_source="$RUNNER_TEMP/dmg-source"
rm -rf "$dmg_source"
mkdir -p "$dmg_source"
cp -R "$staging_path/AgentPanel.app" "$dmg_source/AgentPanel.app"

create-dmg \
  --volname "AgentPanel" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "AgentPanel.app" 150 190 \
  --app-drop-link 450 190 \
  --no-internet-enable \
  "$artifacts_path/$dmg_name" \
  "$dmg_source"
rm -rf "$dmg_source"

echo "Codesigning DMG..."
codesign --force --timestamp \
  --sign "$DEVELOPER_ID_APP_IDENTITY" \
  "$artifacts_path/$dmg_name"

# --- PKG ---
pkg_name="ap-v${VERSION}-macos-arm64.pkg"
echo "Creating PKG: $pkg_name"

# Determine install directory and binary name from CLI_INSTALL_PATH
install_dir=$(dirname "$CLI_INSTALL_PATH")
install_bin=$(basename "$CLI_INSTALL_PATH")

# Setup pkg root directory structure
pkg_root="$RUNNER_TEMP/pkg-root"
rm -rf "$pkg_root"
mkdir -p "$pkg_root/$install_dir"
cp "$staging_path/ap" "$pkg_root/$install_dir/$install_bin"

# Create unsigned component package
unsigned_pkg="$RUNNER_TEMP/ap-unsigned.pkg"
pkgbuild \
  --root "$pkg_root" \
  --identifier "com.agentpanel.cli" \
  --version "$VERSION" \
  --install-location "/" \
  "$unsigned_pkg"

# Sign with installer identity
productsign \
  --sign "$DEVELOPER_ID_INSTALLER_IDENTITY" \
  --timestamp \
  "$unsigned_pkg" \
  "$artifacts_path/$pkg_name"

rm -f "$unsigned_pkg"

# --- Tarball ---
tarball_name="ap-v${VERSION}-macos-arm64.tar.gz"
echo "Creating tarball: $tarball_name"
tar -czf "$artifacts_path/$tarball_name" -C "$staging_path" ap

echo "ci_package: OK"
echo "DMG: $artifacts_path/$dmg_name"
echo "PKG: $artifacts_path/$pkg_name"
echo "Tarball: $artifacts_path/$tarball_name"
