#!/usr/bin/env bash
set -euo pipefail

# Setup signing keychain and import certificates for CI release builds.
#
# Required environment variables:
#   APPLE_API_PRIVATE_KEY_B64
#   DEVELOPER_ID_APP_P12_B64
#   DEVELOPER_ID_APP_P12_PASSWORD
#   DEVELOPER_ID_INSTALLER_P12_B64
#   DEVELOPER_ID_INSTALLER_P12_PASSWORD
#   KEYCHAIN_PASSWORD
#   RUNNER_TEMP

signing_dir="$RUNNER_TEMP/signing"
keychain_path="$RUNNER_TEMP/release.keychain-db"

mkdir -p "$signing_dir"

echo "Decoding signing materials..."
echo "$APPLE_API_PRIVATE_KEY_B64" | base64 --decode > "$signing_dir/AuthKey.p8"
echo "$DEVELOPER_ID_APP_P12_B64" | base64 --decode > "$signing_dir/app.p12"
echo "$DEVELOPER_ID_INSTALLER_P12_B64" | base64 --decode > "$signing_dir/installer.p12"

echo "Creating temporary keychain..."
security create-keychain -p "$KEYCHAIN_PASSWORD" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$keychain_path"
security list-keychains -d user -s "$keychain_path"

echo "Importing application certificate..."
security import "$signing_dir/app.p12" \
  -k "$keychain_path" \
  -P "$DEVELOPER_ID_APP_P12_PASSWORD" \
  -T /usr/bin/codesign

echo "Importing installer certificate..."
security import "$signing_dir/installer.p12" \
  -k "$keychain_path" \
  -P "$DEVELOPER_ID_INSTALLER_P12_PASSWORD" \
  -T /usr/bin/productsign \
  -T /usr/bin/pkgbuild

echo "Setting key partition list..."
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASSWORD" "$keychain_path"

echo "Verifying identities..."
security find-identity -v -p codesigning "$keychain_path"

echo "ci_setup_signing: OK"
