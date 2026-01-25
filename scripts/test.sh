#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

scripts/dev_bootstrap.sh

if [[ ! -d "ProjectWorkspaces.xcodeproj" ]]; then
  echo "error: ProjectWorkspaces.xcodeproj is missing" >&2
  echo "Fix: scripts/regenerate_xcodeproj.sh" >&2
  exit 1
fi

derived_data_path="build/DerivedData"
mkdir -p "$(dirname -- "$derived_data_path")"

echo "Running unit tests (Debug)..."
xcodebuild \
  -project ProjectWorkspaces.xcodeproj \
  -scheme ProjectWorkspaces \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  test \
  CODE_SIGNING_ALLOWED=NO

echo "test: OK"
