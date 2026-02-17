#!/usr/bin/env bash
set -euo pipefail

# Archive the app, export it for Developer ID distribution, and codesign the CLI binary.
#
# Required environment variables:
#   DEVELOPER_ID_APP_IDENTITY  — e.g. "Developer ID Application: Name (TEAMID)"
#   MACOS_DEPLOYMENT_TARGET    — e.g. "16.0"
#   VERSION                    — e.g. "0.1.0"
#   RUNNER_TEMP

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# --- Validate required inputs ---
if [[ -z "${MACOS_DEPLOYMENT_TARGET:-}" ]]; then
  echo "error: MACOS_DEPLOYMENT_TARGET is not set or empty" >&2
  exit 1
fi
if [[ ! "$MACOS_DEPLOYMENT_TARGET" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "error: MACOS_DEPLOYMENT_TARGET must be major.minor (e.g. 16.0), got: $MACOS_DEPLOYMENT_TARGET" >&2
  exit 1
fi

archive_path="$RUNNER_TEMP/AgentPanel.xcarchive"
export_path="$RUNNER_TEMP/export"
staging_path="$RUNNER_TEMP/staging"
derived_data_path="build/DerivedData"

# Extract team ID from identity string: "Developer ID Application: Name (TEAMID)" → "TEAMID"
team_id=$(echo "$DEVELOPER_ID_APP_IDENTITY" | sed 's/.*(\(.*\))/\1/')
if [[ -z "$team_id" || "$team_id" == "$DEVELOPER_ID_APP_IDENTITY" ]]; then
  echo "error: could not extract team ID from DEVELOPER_ID_APP_IDENTITY" >&2
  exit 1
fi
echo "Team ID: $team_id"

# --- Archive ---
echo "Archiving (Release)..."
xcodebuild archive \
  -project AgentPanel.xcodeproj \
  -scheme AgentPanel \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_data_path" \
  MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
  2>&1 | xcbeautify

# --- Generate ExportOptions.plist ---
export_options="$RUNNER_TEMP/ExportOptions.plist"
cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${team_id}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

# --- Export ---
echo "Exporting archive..."
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options" \
  2>&1 | xcbeautify

# --- Verify exported app ---
app_path="$export_path/AgentPanel.app"
if [[ ! -d "$app_path" ]]; then
  echo "error: exported app not found at $app_path" >&2
  ls -la "$export_path/" 2>/dev/null || true
  exit 1
fi

# --- Find and codesign CLI binary ---
cli_candidates=(
  "$archive_path/Products/usr/local/bin/ap"
  "$archive_path/Products/usr/bin/ap"
)
cli_source=""
for candidate in "${cli_candidates[@]}"; do
  if [[ -x "$candidate" ]]; then
    cli_source="$candidate"
    break
  fi
done

if [[ -z "$cli_source" ]]; then
  echo "error: CLI binary 'ap' not found in archive" >&2
  echo "Searching archive Products directory..."
  find "$archive_path/Products" -name "ap" -type f 2>/dev/null || true
  exit 1
fi

echo "Found CLI binary at: $cli_source"
echo "Codesigning CLI binary with hardened runtime..."
codesign --force --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APP_IDENTITY" \
  "$cli_source"
codesign --verify --deep --strict "$cli_source"

# --- Stage artifacts ---
mkdir -p "$staging_path"
cp -R "$app_path" "$staging_path/AgentPanel.app"
cp "$cli_source" "$staging_path/ap"

echo "ci_archive: OK"
echo "App: $staging_path/AgentPanel.app"
echo "CLI: $staging_path/ap"
