#!/usr/bin/env bash
set -euo pipefail

# Integration test for coverage_gate.swift
# Pipes crafted JSON fixtures and verifies output format, sorting, and pass/fail logic.

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

script="scripts/coverage_gate.swift"
pass_count=0
fail_count=0

run_test() {
  local name="$1"
  local expected_exit="$2"
  local json="$3"
  shift 3
  local args=("$@")

  local output
  local actual_exit=0
  output=$(echo "$json" | xcrun swift "$script" "${args[@]}" 2>&1) || actual_exit=$?

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL: $name"
    echo "  Expected exit code $expected_exit, got $actual_exit"
    echo "  Output: $output"
    fail_count=$((fail_count + 1))
    return
  fi

  # Store output for assertion checks by caller
  TEST_OUTPUT="$output"
  pass_count=$((pass_count + 1))
  echo "PASS: $name (exit $actual_exit)"
}

assert_contains() {
  local label="$1"
  local pattern="$2"
  if ! echo "$TEST_OUTPUT" | grep -qF "$pattern"; then
    echo "FAIL: assert_contains($label)"
    echo "  Pattern not found: $pattern"
    echo "  Output: $TEST_OUTPUT"
    fail_count=$((fail_count + 1))
    pass_count=$((pass_count - 1))
    return 1
  fi
  return 0
}

assert_regex() {
  local label="$1"
  local pattern="$2"
  if ! echo "$TEST_OUTPUT" | grep -qE "$pattern"; then
    echo "FAIL: assert_regex($label)"
    echo "  Regex not found: $pattern"
    echo "  Output: $TEST_OUTPUT"
    fail_count=$((fail_count + 1))
    pass_count=$((pass_count - 1))
    return 1
  fi
  return 0
}

assert_line_before() {
  local label="$1"
  local first="$2"
  local second="$3"
  local first_line second_line
  first_line=$(echo "$TEST_OUTPUT" | grep -nF "$first" | head -1 | cut -d: -f1)
  second_line=$(echo "$TEST_OUTPUT" | grep -nF "$second" | head -1 | cut -d: -f1)
  if [[ -z "$first_line" || -z "$second_line" ]]; then
    echo "FAIL: assert_line_before($label) — pattern not found"
    echo "  first='$first' (line $first_line), second='$second' (line $second_line)"
    fail_count=$((fail_count + 1))
    pass_count=$((pass_count - 1))
    return 1
  fi
  if [[ "$first_line" -ge "$second_line" ]]; then
    echo "FAIL: assert_line_before($label)"
    echo "  '$first' (line $first_line) should appear before '$second' (line $second_line)"
    fail_count=$((fail_count + 1))
    pass_count=$((pass_count - 1))
    return 1
  fi
  return 0
}

# --- Fixtures ---

# Two targets, multiple files with varying coverage
fixture_passing='{
  "targets": [
    {
      "name": "CoreLib.framework",
      "coveredLines": 900,
      "executableLines": 1000,
      "lineCoverage": 0.9,
      "files": [
        {"name": "HighCov.swift", "coveredLines": 500, "executableLines": 500, "lineCoverage": 1.0},
        {"name": "LowCov.swift", "coveredLines": 200, "executableLines": 300, "lineCoverage": 0.666},
        {"name": "MidCov.swift", "coveredLines": 200, "executableLines": 200, "lineCoverage": 1.0}
      ]
    },
    {
      "name": "CLILib.framework",
      "coveredLines": 180,
      "executableLines": 200,
      "lineCoverage": 0.9,
      "files": [
        {"name": "CLI.swift", "coveredLines": 80, "executableLines": 100, "lineCoverage": 0.8},
        {"name": "Args.swift", "coveredLines": 100, "executableLines": 100, "lineCoverage": 1.0}
      ]
    }
  ]
}'

fixture_failing='{
  "targets": [
    {
      "name": "CoreLib.framework",
      "coveredLines": 400,
      "executableLines": 1000,
      "lineCoverage": 0.4,
      "files": [
        {"name": "Bad.swift", "coveredLines": 100, "executableLines": 500, "lineCoverage": 0.2},
        {"name": "Good.swift", "coveredLines": 300, "executableLines": 500, "lineCoverage": 0.6}
      ]
    }
  ]
}'

# --- Tests ---

echo "=== coverage_gate.swift integration tests ==="
echo ""

# Test 1: Passing gate with per-file summary
run_test "passing gate shows target summary" 0 \
  "$fixture_passing" \
  --minPercent 85 --target "CoreLib.framework" --target "CLILib.framework"
assert_contains "target summary" "CoreLib.framework: 90.00% (900/1000)"
assert_contains "CLI target summary" "CLILib.framework: 90.00% (180/200)"
assert_contains "total line" "TOTAL (selected): 90.00%"
assert_contains "min required line" "MIN REQUIRED: 85.00%"

# Test 2: Per-file summary section present
run_test "per-file summary section present" 0 \
  "$fixture_passing" \
  --minPercent 85 --target "CoreLib.framework" --target "CLILib.framework"
assert_contains "per-file header" "Per-file coverage:"
assert_contains "core target in file summary" "CoreLib.framework:"
assert_contains "cli target in file summary" "CLILib.framework:"

# Test 3: Files sorted by coverage % ascending (lowest first)
run_test "files sorted by coverage ascending" 0 \
  "$fixture_passing" \
  --minPercent 85 --target "CoreLib.framework"
# LowCov.swift (66.67%) should appear before HighCov.swift (100%) and MidCov.swift (100%)
assert_line_before "low before high" "LowCov.swift" "HighCov.swift"
assert_line_before "low before mid" "LowCov.swift" "MidCov.swift"

# Test 4: Per-file format includes filename, percentage, line counts
run_test "per-file format" 0 \
  "$fixture_passing" \
  --minPercent 85 --target "CLILib.framework"
assert_regex "file format" "CLI\.swift.*80\.00%.*\(80/100\)"
assert_regex "file format 2" "Args\.swift.*100\.00%.*\(100/100\)"

# Test 5: Failing gate exits 1
run_test "failing gate exits 1" 1 \
  "$fixture_failing" \
  --minPercent 90 --target "CoreLib.framework"
assert_contains "gate failed message" "coverage gate failed"

# Test 6: Failing gate still shows per-file summary
run_test "failing gate shows per-file" 1 \
  "$fixture_failing" \
  --minPercent 90 --target "CoreLib.framework"
assert_contains "per-file in failing" "Per-file coverage:"
assert_line_before "bad before good in failing" "Bad.swift" "Good.swift"

echo ""
echo "=== Results: $pass_count passed, $fail_count failed ==="

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
