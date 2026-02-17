#!/usr/bin/env bash
set -euo pipefail

# Notarize and staple a single artifact.
#
# Usage: ci_notarize.sh <artifact-path>
#
# Required environment variables:
#   APPLE_API_KEY_ID
#   APPLE_API_ISSUER_ID
#   RUNNER_TEMP            — AuthKey.p8 must exist at $RUNNER_TEMP/signing/AuthKey.p8

if [[ $# -ne 1 ]]; then
  echo "usage: ci_notarize.sh <artifact-path>" >&2
  exit 1
fi

artifact="$1"
api_key="$RUNNER_TEMP/signing/AuthKey.p8"

if [[ ! -f "$artifact" ]]; then
  echo "error: artifact not found: $artifact" >&2
  exit 1
fi
if [[ ! -f "$api_key" ]]; then
  echo "error: API key not found: $api_key" >&2
  exit 1
fi

echo "Submitting for notarization: $(basename "$artifact")"
xcrun notarytool submit "$artifact" \
  --key "$api_key" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait \
  --timeout 30m

echo "Stapling notarization ticket..."
xcrun stapler staple -v "$artifact"

echo "Validating staple..."
xcrun stapler validate -v "$artifact"

echo "ci_notarize: OK — $(basename "$artifact")"
