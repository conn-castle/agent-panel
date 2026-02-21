#!/usr/bin/env bash
# ci_preflight.sh — Validates release-readiness on every CI run.
# Catches configuration and packaging issues before a release tag is pushed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
errors=0
runner_label=""

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

  runner_label=$(grep -E '^[[:space:]]*runs-on:[[:space:]]*' "$workflow" | head -1 | sed -E 's/^[[:space:]]*runs-on:[[:space:]]*//')
  if [[ "$runner_label" == "macos-26" ]]; then
    echo "PASS: Release workflow runs on macos-26"
  else
    fail "Release workflow runner is '$runner_label' (expected macos-26)"
  fi

  if grep -q 'uses: maxim-lobanov/setup-xcode@v1' "$workflow"; then
    echo "PASS: Release workflow selects Xcode with setup-xcode"
  else
    fail "Release workflow missing setup-xcode step"
  fi

  if grep -q 'xcode-version: latest-stable' "$workflow"; then
    echo "PASS: Release workflow uses latest-stable Xcode channel"
  else
    fail "Release workflow does not use xcode-version: latest-stable"
  fi

  if grep -q '\-lt 26' "$workflow"; then
    echo "PASS: Release workflow enforces Xcode major >= 26"
  else
    fail "Release workflow does not enforce Xcode major >= 26"
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
  # ci_archive.sh must codesign with hardened runtime and entitlements
  if grep -q 'options runtime' "$archive_script" && grep -q 'entitlements' "$archive_script"; then
    echo "PASS: ci_archive.sh codesigns with hardened runtime and entitlements"
  else
    fail "ci_archive.sh missing hardened runtime or entitlements in codesign — notarization will fail"
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

# 10. project.yml deployment target is within release runner SDK major range
deploy_target=$(grep 'macOS:' "$REPO_ROOT/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
if [[ -n "$deploy_target" ]]; then
  deploy_major=$(echo "$deploy_target" | cut -d. -f1)
  if [[ "$runner_label" =~ ^macos-([0-9]+)$ ]]; then
    runner_major="${BASH_REMATCH[1]}"
    if [[ "$deploy_major" -gt "$runner_major" ]]; then
      fail "project.yml deployment target $deploy_target exceeds release runner SDK major ($runner_label) — archive will fail"
    else
      echo "PASS: Deployment target $deploy_target (major $deploy_major) is within release runner SDK major ($runner_label)"
    fi
  elif [[ "$runner_label" == "macos-latest" ]]; then
    echo "PASS: Release runner is macos-latest; deployment target $deploy_target accepted without strict major check"
  else
    fail "Unable to infer release runner SDK major from runs-on label '$runner_label'"
  fi
else
  fail "Could not read deployment target from project.yml"
fi

# 11. ci_setup_signing.sh preserves existing keychain search list
signing_script="$REPO_ROOT/scripts/ci_setup_signing.sh"
if [[ -f "$signing_script" ]]; then
  # The script must NOT replace the keychain list (removing login.keychain-db breaks
  # IDEDistribution). It must preserve existing keychains when adding the release keychain.
  if grep -q 'list-keychains -d user -s.*\$' "$signing_script" && grep -q 'existing_keychains\|list-keychains.*-d user' "$signing_script"; then
    echo "PASS: ci_setup_signing.sh preserves existing keychain search list"
  else
    fail "ci_setup_signing.sh may replace the keychain search list — exportArchive will fail with empty distribution methods"
  fi
  # The .p12 only has the leaf cert. IDEDistribution needs the Apple intermediate CA
  # to validate the chain for developer-id distribution. Without it: "Unknown Distribution Error".
  if grep -q 'DeveloperIDG2CA.cer' "$signing_script"; then
    echo "PASS: ci_setup_signing.sh downloads Apple Developer ID G2 intermediate certificate"
  else
    fail "ci_setup_signing.sh missing Apple Developer ID G2 intermediate cert download — exportArchive will fail"
  fi
fi

# 12. Identity.swift buildVersion matches MARKETING_VERSION
identity_swift="$REPO_ROOT/AgentPanelCore/Identity.swift"
if [[ -f "$identity_swift" ]]; then
  swift_version=$(grep 'static let buildVersion' "$identity_swift" | head -1 | sed 's/.*= *"\([^"]*\)".*/\1/')
  if [[ -z "$swift_version" ]]; then
    fail "Could not read buildVersion from Identity.swift"
  elif [[ "$swift_version" != "$version" ]]; then
    fail "Identity.swift buildVersion '$swift_version' does not match MARKETING_VERSION '$version' — CLI will report wrong version"
  else
    echo "PASS: Identity.swift buildVersion matches MARKETING_VERSION ($version)"
  fi
else
  fail "Identity.swift not found at $identity_swift"
fi

echo ""
if [[ $errors -gt 0 ]]; then
  echo "=== $errors preflight check(s) FAILED ==="
  exit 1
else
  echo "=== All preflight checks passed ==="
fi
