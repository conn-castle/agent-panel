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

derived_data_path=".agent-layer/tmp/DerivedData"
mkdir -p "$(dirname -- "$derived_data_path")"

echo "Resolving SwiftPM packages (if any)..."
xcodebuild \
  -project ProjectWorkspaces.xcodeproj \
  -scheme ProjectWorkspaces \
  -derivedDataPath "$derived_data_path" \
  -resolvePackageDependencies

echo "Building (Debug)..."
xcodebuild \
  -project ProjectWorkspaces.xcodeproj \
  -scheme ProjectWorkspaces \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$derived_data_path" \
  build \
  CODE_SIGNING_ALLOWED=NO

app_path="$derived_data_path/Build/Products/Debug/ProjectWorkspaces.app"
alt_app_path="$derived_data_path/Build/Products/Debug/ProjectWorkspacesApp.app"
cli_path="$derived_data_path/Build/Products/Debug/pwctl"

if [[ ! -d "$app_path" ]]; then
  echo "error: Expected app bundle not found at: $app_path" >&2
  if [[ -d "$alt_app_path" ]]; then
    echo "error: Found app bundle at: $alt_app_path (expected ProjectWorkspaces.app)" >&2
    echo "Fix: Ensure ProjectWorkspacesApp sets PRODUCT_NAME=ProjectWorkspaces in project.yml, then regenerate ProjectWorkspaces.xcodeproj" >&2
  else
    echo "Fix: Ensure the ProjectWorkspaces scheme builds ProjectWorkspacesApp as an app product" >&2
  fi
  exit 1
fi

if [[ ! -x "$cli_path" ]]; then
  echo "error: Expected CLI binary not found at: $cli_path" >&2
  echo "Fix: Ensure the ProjectWorkspaces scheme builds pwctl" >&2
  exit 1
fi

echo "build: OK"
echo "App: $app_path"
echo "CLI: $cli_path"
