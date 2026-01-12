#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v xcode-select >/dev/null 2>&1; then
  echo "error: xcode-select is required (install Xcode)" >&2
  exit 1
fi

developer_dir=""
if ! developer_dir="$(xcode-select -p 2>/dev/null)"; then
  echo "error: Xcode developer directory is not configured (xcode-select -p failed)" >&2
  echo "Fix: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if [[ -z "$developer_dir" ]]; then
  echo "error: Xcode developer directory is empty (xcode-select -p returned nothing)" >&2
  echo "Fix: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if [[ "$developer_dir" == "/Library/Developer/CommandLineTools"* ]]; then
  echo "error: Full Xcode must be selected (currently using Command Line Tools: $developer_dir)" >&2
  echo "Fix: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  echo "Fix: If you use Xcode-beta, switch to /Applications/Xcode-beta.app/Contents/Developer" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required (install Xcode and select it via xcode-select)" >&2
  echo "Fix: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: xcodebuild is not usable (xcodebuild -version failed)" >&2
  echo "Fix: Ensure Xcode is installed and selected via xcode-select" >&2
  exit 1
fi

if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  echo "error: Xcode first-launch tasks are not complete" >&2
  echo "Fix: sudo xcodebuild -runFirstLaunch" >&2
  echo "Fix: sudo xcodebuild -license accept" >&2
  exit 1
fi

echo "dev_bootstrap: OK (Xcode toolchain selected and ready)"

