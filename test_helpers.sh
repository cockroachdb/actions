#!/usr/bin/env bash
# Shared test helpers for all test files in this repository.
#
# Usage:
#   source test_helpers.sh
#   expect_success "test name" command [args...]
#   expect_success_output "test name" "expected output" command [args...]
#   expect_failure "test name" command [args...]
#   expect_failure_output "test name" "expected output" command [args...]
#   print_results

# Source actions_helpers.sh to get check_contains and check_contains_pattern
TEST_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=actions_helpers.sh
source "$TEST_HELPERS_DIR/actions_helpers.sh"

PASS=0
FAIL=0

_run_test() {
  local name="$1"
  local expected_exit="$2"  # exact code, or "nonzero" for any non-zero
  local expected_output="$3"
  shift 3

  local output exit_code
  output=$("$@" 2>&1) && exit_code=0 || exit_code=$?

  if [ "$expected_exit" = "nonzero" ]; then
    if [ "$exit_code" -eq 0 ]; then
      echo "FAIL: $name — expected non-zero exit, got 0"
      echo "  output: $output"
      FAIL=$((FAIL + 1))
      return
    fi
  elif [ "$exit_code" -ne "$expected_exit" ]; then
    echo "FAIL: $name — expected exit $expected_exit, got $exit_code"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
    return
  fi

  if [ -n "$expected_output" ] && ! printf '%s\n' "$output" | check_contains "$expected_output"; then
    echo "FAIL: $name — expected output containing: $expected_output"
    echo "  actual: $output"
    FAIL=$((FAIL + 1))
    return
  fi

  echo "PASS: $name"
  PASS=$((PASS + 1))
}

# expect_success "test name" command [args...]
# Asserts the command exits 0.
expect_success() {
  local name="$1"; shift
  _run_test "$name" 0 "" "$@"
}

# expect_success_output "test name" "expected output substring" command [args...]
# Asserts the command exits 0 and output contains the expected substring.
expect_success_output() {
  local name="$1"; shift
  local expected_output="$1"; shift
  _run_test "$name" 0 "$expected_output" "$@"
}

# expect_failure "test name" command [args...]
# Asserts the command exits non-zero.
expect_failure() {
  local name="$1"; shift
  _run_test "$name" "nonzero" "" "$@"
}

# expect_failure_output "test name" "expected output substring" command [args...]
# Asserts the command exits non-zero and output contains the expected substring.
expect_failure_output() {
  local name="$1"; shift
  local expected_output="$1"; shift
  _run_test "$name" "nonzero" "$expected_output" "$@"
}

# expect_step_output "test name" "key" "expected_value"
# Asserts that GITHUB_OUTPUT contains key=expected_value.
# Checks the last occurrence of the key so tests that reuse the same file work.
expect_step_output() {
  local name="$1" key="$2" expected="$3"
  local actual=""
  if [ ! -f "${GITHUB_OUTPUT}" ]; then
    echo "FAIL: $name — GITHUB_OUTPUT file does not exist"
    FAIL=$((FAIL + 1))
    return
  fi
  if check_contains "${key}=" "${GITHUB_OUTPUT}"; then
    actual=$(grep --fixed-strings "${key}=" "${GITHUB_OUTPUT}" | tail -1 | cut -d= -f2-)
  fi
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name — expected output $key=$expected, got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

# expect_files_in_commit file1 [file2 ...]
# Asserts that all listed files are in the last commit
expect_files_in_commit() {
  for file in "$@"; do
    if ! git diff --name-only HEAD~1 HEAD | grep --quiet --fixed-strings --line-regexp "$file"; then
      echo "Expected $file to be in commit, but it wasn't" >&2
      return 1
    fi
  done
}

# expect_files_not_in_commit file1 [file2 ...]
# Asserts that none of the listed files are in the last commit
expect_files_not_in_commit() {
  for file in "$@"; do
    if git diff --name-only HEAD~1 HEAD | grep --quiet --fixed-strings --line-regexp "$file"; then
      echo "Expected $file NOT to be in commit, but it was" >&2
      return 1
    fi
  done
}

# expect_diff "test name" original_content expected_diff transformation_command
# Runs transformation_command on original_content and verifies the diff contains expected_diff.
#
# Example:
#   expect_diff "adds version header" \
#     "## [Unreleased]\n- Change" \
#     "## [1.0.0] - 2026-04-04" \
#     test_update_changelog "1.0.0" "2026-04-04"
expect_diff() {
  local name="$1" original="$2" expected_diff="$3"
  shift 3

  # Create temp directory for before/after comparison
  local tmpdir
  tmpdir=$(mktemp -d)

  # Write original content to file
  echo "$original" > "$tmpdir/before"

  # Run transformation command and capture output
  local output exit_code
  output=$("$@" 2>&1)
  exit_code=$?

  # Fail if transformation command failed
  if [ "$exit_code" -ne 0 ]; then
    echo "FAIL: $name — command failed with exit code $exit_code"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
    rm -rf "$tmpdir"
    return
  fi

  # Write transformed content to file
  echo "$output" > "$tmpdir/after"

  # Generate unified diff
  # diff exits with 0 (identical), 1 (differ), or 2 (error)
  local actual_diff diff_exit
  actual_diff=$(diff --unified "$tmpdir/before" "$tmpdir/after" 2>&1) && diff_exit=0 || diff_exit=$?

  # Exit code 2 means error (not just files differing)
  if [ "$diff_exit" -eq 2 ]; then
    echo "FAIL: $name — diff command failed"
    echo "  diff error: $actual_diff"
    FAIL=$((FAIL + 1))
    rm -rf "$tmpdir"
    return
  fi

  # Check if diff contains the expected string (exact match, not regex)
  if echo "$actual_diff" | check_contains "$expected_diff"; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name — diff doesn't contain expected string"
    echo "  expected to find: $expected_diff"
    echo "  actual diff:"
    echo "$actual_diff"
    FAIL=$((FAIL + 1))
  fi

  # Clean up temp directory
  rm -rf "$tmpdir"
}

print_results() {
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
}
