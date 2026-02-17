#!/usr/bin/env bash
# ci_preflight.sh — Validates release-readiness on every CI run.
# Catches configuration and packaging issues before a release tag is pushed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
errors=0

fail() {
  echo "FAIL: $1" >&2
  errors=$((errors + 1))
}

echo "=== Release preflight checks ==="

# 1. MARKETING_VERSION in project.yml must be valid semver
version=$(grep 'MARKETING_VERSION' "$REPO_ROOT/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
if [[ -z "$version" ]]; then
  fail "MARKETING_VERSION not found in project.yml"
elif [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "MARKETING_VERSION '$version' is not valid semver (expected X.Y.Z)"
else
  echo "PASS: MARKETING_VERSION=$version"
fi

# 2. CURRENT_PROJECT_VERSION in project.yml must be a positive integer
build_version=$(grep 'CURRENT_PROJECT_VERSION' "$REPO_ROOT/project.yml" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '[:space:]')
if [[ -z "$build_version" ]]; then
  fail "CURRENT_PROJECT_VERSION not found in project.yml"
elif [[ ! "$build_version" =~ ^[1-9][0-9]*$ ]]; then
  fail "CURRENT_PROJECT_VERSION '$build_version' is not a positive integer"
else
  echo "PASS: CURRENT_PROJECT_VERSION=$build_version"
fi

# 3. Info.plist uses build-setting variables (not hardcoded)
plist="$REPO_ROOT/AgentPanelApp/Info.plist"
if [[ ! -f "$plist" ]]; then
  fail "Info.plist not found at $plist"
else
  if grep -q '<string>$(MARKETING_VERSION)</string>' "$plist"; then
    echo "PASS: Info.plist CFBundleShortVersionString uses \$(MARKETING_VERSION)"
  else
    fail "Info.plist CFBundleShortVersionString is not \$(MARKETING_VERSION) — version will be wrong in built app"
  fi
  if grep -q '<string>$(CURRENT_PROJECT_VERSION)</string>' "$plist"; then
    echo "PASS: Info.plist CFBundleVersion uses \$(CURRENT_PROJECT_VERSION)"
  else
    fail "Info.plist CFBundleVersion is not \$(CURRENT_PROJECT_VERSION) — build number will be wrong in built app"
  fi
fi

# 4. Entitlements file exists
entitlements="$REPO_ROOT/release/AgentPanel.entitlements"
if [[ -f "$entitlements" ]]; then
  echo "PASS: Entitlements file exists"
else
  fail "Entitlements file missing at release/AgentPanel.entitlements"
fi

# 5. CI scripts exist and are executable
ci_scripts=(
  ci_setup_signing.sh
  ci_archive.sh
  ci_package.sh
  ci_notarize.sh
  ci_release_validate.sh
)
for script in "${ci_scripts[@]}"; do
  path="$REPO_ROOT/scripts/$script"
  if [[ ! -f "$path" ]]; then
    fail "CI script missing: scripts/$script"
  elif [[ ! -x "$path" ]]; then
    fail "CI script not executable: scripts/$script"
  else
    echo "PASS: scripts/$script"
  fi
done

# 6. Release workflow exists and references the release environment
workflow="$REPO_ROOT/.github/workflows/release.yml"
if [[ ! -f "$workflow" ]]; then
  fail "Release workflow missing at .github/workflows/release.yml"
else
  if grep -q 'environment: release' "$workflow"; then
    echo "PASS: Release workflow uses 'release' environment"
  else
    fail "Release workflow does not reference 'release' environment"
  fi
  # Verify tag trigger pattern
  if grep -q "tags:.*'v\*'" "$workflow" || grep -q 'tags:.*"v\*"' "$workflow"; then
    echo "PASS: Release workflow triggers on v* tags"
  else
    fail "Release workflow does not trigger on v* tags"
  fi
fi

# 7. project.yml has Release code signing configured for app and CLI
if grep -A2 'CODE_SIGN_STYLE:' "$REPO_ROOT/project.yml" | grep -q 'Manual'; then
  echo "PASS: Release code signing configured (Manual)"
else
  fail "project.yml missing Release code signing configuration (CODE_SIGN_STYLE: Manual)"
fi

# 8. ci_archive.sh passes DEVELOPMENT_TEAM to xcodebuild archive
archive_script="$REPO_ROOT/scripts/ci_archive.sh"
if [[ -f "$archive_script" ]]; then
  if grep -q 'DEVELOPMENT_TEAM=' "$archive_script"; then
    echo "PASS: ci_archive.sh passes DEVELOPMENT_TEAM to xcodebuild"
  else
    fail "ci_archive.sh does not pass DEVELOPMENT_TEAM to xcodebuild — archive will fail with 'requires a development team'"
  fi
  # ExportOptions.plist must include destination key for developer-id export (Xcode 14+)
  if grep -q '<key>destination</key>' "$archive_script"; then
    echo "PASS: ci_archive.sh ExportOptions includes destination key"
  else
    fail "ci_archive.sh ExportOptions.plist missing 'destination' key — export will fail on Xcode 14+"
  fi
fi

# 9. Release workflow does not override MACOSX_DEPLOYMENT_TARGET
# The deployment target is set in project.yml (single source of truth).
# Overriding via env var causes failures when the runner SDK is older than the target.
if [[ -f "$workflow" ]]; then
  if grep -q 'MACOS_DEPLOYMENT_TARGET\|MACOSX_DEPLOYMENT_TARGET' "$workflow"; then
    fail "Release workflow overrides deployment target — remove it; project.yml is the single source of truth"
  else
    echo "PASS: Release workflow does not override deployment target"
  fi
fi

# 10. project.yml deployment target is within CI runner SDK range
# The macos-15 runner has Xcode with SDK max ~15.5. Deployment targets above
# this produce warnings but still build. Flag targets above 15 (major) as errors
# since they indicate an SDK that the runner definitely doesn't have.
deploy_target=$(grep 'macOS:' "$REPO_ROOT/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
if [[ -n "$deploy_target" ]]; then
  deploy_major=$(echo "$deploy_target" | cut -d. -f1)
  if [[ "$deploy_major" -gt 15 ]]; then
    fail "project.yml deployment target $deploy_target exceeds CI runner SDK (macOS 15.x) — archive will fail"
  else
    echo "PASS: Deployment target $deploy_target (major $deploy_major) is within CI runner SDK range"
  fi
else
  fail "Could not read deployment target from project.yml"
fi

echo ""
if [[ $errors -gt 0 ]]; then
  echo "=== $errors preflight check(s) FAILED ==="
  exit 1
else
  echo "=== All preflight checks passed ==="
fi
