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

echo "Resolving SwiftPM packages (if any)..."
xcodebuild \
  -project AgentPanel.xcodeproj \
  -scheme AgentPanelDev \
  -derivedDataPath "$derived_data_path" \
  -resolvePackageDependencies \
  2>&1 | xcbeautify

echo "Building dev app (Debug)..."
xcodebuild \
  -project AgentPanel.xcodeproj \
  -scheme AgentPanelDev \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | xcbeautify

app_path="$derived_data_path/Build/Products/Debug/AgentPanel Dev.app"
alt_app_path="$derived_data_path/Build/Products/Debug/AgentPanelDev.app"

if [[ ! -d "$app_path" ]]; then
  echo "error: Expected dev app bundle not found at: $app_path" >&2
  if [[ -d "$alt_app_path" ]]; then
    echo "error: Found app bundle at: $alt_app_path (expected AgentPanel Dev.app)" >&2
    echo "Fix: Ensure the AgentPanelDev target sets PRODUCT_NAME=AgentPanel Dev in project.yml, then regenerate AgentPanel.xcodeproj" >&2
  else
    echo "Fix: Ensure the AgentPanelDev scheme builds the AgentPanel Dev app product" >&2
  fi
  exit 1
fi

echo "build-dev: OK"
echo "App: $app_path"
