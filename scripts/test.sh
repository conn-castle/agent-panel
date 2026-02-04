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
  test \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | xcbeautify

echo "test: OK"
