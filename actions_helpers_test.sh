#!/usr/bin/env bash
# Tests for actions_helpers.sh helpers.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ./test_helpers.sh
source ./actions_helpers.sh

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# --- log_* tests ---

test_log_error() {
  local output
  output=$(log_error "something broke")
  [ "$output" = "::error::something broke" ]
}
expect_success "log_error: formats correctly" test_log_error

test_log_warning() {
  local output
  output=$(log_warning "watch out")
  [ "$output" = "::warning::watch out" ]
}
expect_success "log_warning: formats correctly" test_log_warning

test_log_notice() {
  local output
  output=$(log_notice "fyi")
  [ "$output" = "::notice::fyi" ]
}
expect_success "log_notice: formats correctly" test_log_notice

# --- set_output tests ---

test_set_output() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_single"
  touch "$GITHUB_OUTPUT"
  set_output "mykey" "myvalue"
  check_contains 'mykey=myvalue' "$GITHUB_OUTPUT"
}
expect_success "set_output: writes key=value" test_set_output

test_set_output_empty_value() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_empty"
  touch "$GITHUB_OUTPUT"
  set_output "mykey" ""
  check_contains 'mykey=' "$GITHUB_OUTPUT"
}
expect_success "set_output: handles empty value" test_set_output_empty_value

# --- set_output_multiline tests ---

test_set_output_multiline() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_multi"
  touch "$GITHUB_OUTPUT"
  set_output_multiline "desc" "line one
line two"
  check_contains 'line one' "$GITHUB_OUTPUT" && check_contains 'line two' "$GITHUB_OUTPUT"
}
expect_success "set_output_multiline: writes multiline content" test_set_output_multiline

test_set_output_multiline_delimiters() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_delim"
  touch "$GITHUB_OUTPUT"
  set_output_multiline "desc" "content"
  # Should have opening delimiter (desc<<GHEOF_...) and closing delimiter (GHEOF_...)
  check_contains_pattern '^desc<<GHEOF_' "$GITHUB_OUTPUT" && check_contains_pattern '^GHEOF_' "$GITHUB_OUTPUT"
}
expect_success "set_output_multiline: uses GHEOF delimiters" test_set_output_multiline_delimiters

test_set_output_multiline_empty() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_multi_empty"
  touch "$GITHUB_OUTPUT"
  set_output_multiline "desc" ""
  check_contains_pattern '^desc<<GHEOF_' "$GITHUB_OUTPUT"
}
expect_success "set_output_multiline: handles empty value" test_set_output_multiline_empty

# --- require_command tests ---

test_require_command_found() { require_command bash; }
expect_success "require_command: finds bash" test_require_command_found

test_require_command_missing() { require_command nonexistent_cmd_xyz; }
expect_failure "require_command: fails for missing command" test_require_command_missing

# --- get_base_branch tests ---

test_get_base_branch_provided() {
  local result
  result=$(get_base_branch "my-branch" "owner/repo" 2>&1)
  echo "$result" | check_contains "my-branch"
}
expect_success "get_base_branch: returns provided branch" test_get_base_branch_provided

test_get_base_branch_parses_github_json_develop() {
  # Mock gh to return actual GitHub API JSON format (verified format)
  # This tests the jq parsing: .defaultBranchRef.name
  gh() {
    if [[ "$*" == *"repo view"* ]]; then
      echo '{"defaultBranchRef":{"name":"develop"}}'
    fi
  }
  export -f gh

  local result
  result=$(get_base_branch "" "owner/repo" 2>&1)
  echo "$result" | check_contains "develop"

  unset -f gh
}
expect_success "get_base_branch: parses GitHub JSON for develop branch" test_get_base_branch_parses_github_json_develop

test_get_base_branch_parses_github_json_null() {
  # Test null defaultBranchRef (empty repo case)
  gh() {
    if [[ "$*" == *"repo view"* ]]; then
      echo '{"defaultBranchRef":null}'
    fi
  }
  export -f gh

  local result
  result=$(get_base_branch "" "owner/repo" 2>&1)
  # jq outputs "null" as literal string, which should be treated as empty
  echo "$result" | check_contains "main"

  unset -f gh
}
expect_success "get_base_branch: handles null defaultBranchRef" test_get_base_branch_parses_github_json_null

test_get_base_branch_parses_branch_with_slash() {
  # Test branch names with slashes (e.g., release/v2.0)
  gh() {
    if [[ "$*" == *"repo view"* ]]; then
      echo '{"defaultBranchRef":{"name":"release/v2.0"}}'
    fi
  }
  export -f gh

  local result
  result=$(get_base_branch "" "owner/repo" 2>&1)
  echo "$result" | check_contains "release/v2.0"

  unset -f gh
}
expect_success "get_base_branch: handles branch names with slashes" test_get_base_branch_parses_branch_with_slash

test_get_base_branch_gh_failure() {
  # Test in a directory that's not a git repo - gh should fail
  (
    cd "$TMPDIR_TEST"
    local result
    result=$(get_base_branch "" "owner/repo" 2>&1)
    echo "$result" | check_contains "main"
  )
}
expect_success "get_base_branch: falls back to main when gh fails" test_get_base_branch_gh_failure

print_results
