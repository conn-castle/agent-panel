#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

scripts/dev_bootstrap.sh

if [[ ! -d "AgentPanel.xcodeproj" ]]; then
  echo "error: AgentPanel.xcodeproj is missing" >&2
  echo "Fix: scripts/regenerate_xcodeproj.sh" >&2
  exit 1
fi

derived_data_path="build/DerivedData"
mkdir -p "$(dirname -- "$derived_data_path")"

result_bundle_path="build/TestResults/Test-AgentPanel.xcresult"
mkdir -p "$(dirname -- "$result_bundle_path")"
if [[ -e "$result_bundle_path" ]]; then
  if [[ "$result_bundle_path" != build/TestResults/*.xcresult ]]; then
    echo "error: refusing to delete unexpected result bundle path: $result_bundle_path" >&2
    exit 1
  fi
  rm -rf "$result_bundle_path"
fi

if ! command -v xcbeautify &>/dev/null; then
  echo "error: xcbeautify not found" >&2
  echo "Fix: brew install xcbeautify" >&2
  exit 1
fi

echo "Running unit tests (Debug)..."
xcodebuild \
  -project AgentPanel.xcodeproj \
  -scheme AgentPanel \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  -resultBundlePath "$result_bundle_path" \
  -enableCodeCoverage YES \
  test \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | xcbeautify

scripts/coverage_gate.sh "$result_bundle_path"

echo "test: OK"
