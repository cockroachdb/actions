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

PASS=0
FAIL=0

# Assert that input contains a given substring.
# Usage: check_contains "expected" "$file"   (reads file)
#        cmd | check_contains "expected"     (reads stdin)
check_contains() {
  if [ $# -ge 2 ]; then
    grep --quiet --fixed-strings -- "$1" "$2"
  else
    grep --quiet --fixed-strings -- "$1"
  fi
}

# Assert that input matches a given regex pattern.
# Usage: check_contains_pattern "^prefix" "$file"   (reads file)
#        cmd | check_contains_pattern "^prefix"      (reads stdin)
check_contains_pattern() {
  if [ $# -ge 2 ]; then
    grep --quiet -- "$1" "$2"
  else
    grep --quiet -- "$1"
  fi
}

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

  if [ -n "$expected_output" ] && ! printf '%s\n' "$output" | grep --quiet --fixed-strings -- "$expected_output"; then
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
  if grep --quiet --fixed-strings "${key}=" "${GITHUB_OUTPUT}"; then
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

print_results() {
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
}
