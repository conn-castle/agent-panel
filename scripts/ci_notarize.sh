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
submit_output_file="$RUNNER_TEMP/notarytool-submit-output.txt"
# Disable pipefail for this pipeline so we can capture notarytool's exit code
# directly via PIPESTATUS[0], unaffected by tee's exit code.
set +o pipefail
xcrun notarytool submit "$artifact" \
  --key "$api_key" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait \
  --timeout 30m \
  2>&1 | tee "$submit_output_file"
submit_exit=${PIPESTATUS[0]}
set -o pipefail

if [[ $submit_exit -ne 0 ]]; then
  echo "error: notarytool submit failed with exit code $submit_exit" >&2
  # Extract submission ID and fetch the log for debugging
  submission_id=$(grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$submit_output_file" | head -1)
  if [[ -n "$submission_id" ]]; then
    echo "Fetching notarization log for submission $submission_id..."
    xcrun notarytool log "$submission_id" \
      --key "$api_key" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER_ID" \
      2>&1 || true
  else
    echo "warning: could not extract submission ID from notarytool output" >&2
  fi
  exit 1
fi

echo "Stapling notarization ticket..."
xcrun stapler staple -v "$artifact"

echo "Validating staple..."
xcrun stapler validate -v "$artifact"

echo "ci_notarize: OK — $(basename "$artifact")"
