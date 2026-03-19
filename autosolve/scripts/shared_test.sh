#!/usr/bin/env bash
# Tests for shared.sh functions.
# shellcheck disable=SC2034  # Variables are read by sourced functions
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../test_helpers.sh
source ../../actions_helpers.sh
source ./shared.sh

# --- validate_inputs tests ---

test_validate_no_input() { INPUT_PROMPT=; INPUT_SKILL=; validate_inputs; }
expect_failure_output "validate_inputs: no prompt or skill" "At least one of" test_validate_no_input

test_validate_prompt() { INPUT_PROMPT='fix it'; validate_inputs; }
expect_success "validate_inputs: prompt only" test_validate_prompt

test_validate_skill() { INPUT_SKILL='skill.md'; validate_inputs; }
expect_success "validate_inputs: skill only" test_validate_skill

test_validate_pr_missing() { INPUT_PROMPT='fix'; INPUT_CREATE_PR=true; INPUT_FORK_OWNER=; INPUT_FORK_REPO=; INPUT_FORK_PUSH_TOKEN=; INPUT_PR_CREATE_TOKEN=; validate_inputs; }
expect_failure_output "validate_inputs: create_pr missing fork config" "fork_owner" test_validate_pr_missing

test_validate_pr_ok() { INPUT_PROMPT='fix'; INPUT_CREATE_PR=true; INPUT_FORK_OWNER=bot; INPUT_FORK_REPO=repo; INPUT_FORK_PUSH_TOKEN=tok; INPUT_PR_CREATE_TOKEN=tok; validate_inputs; }
expect_success "validate_inputs: create_pr with all fork config" test_validate_pr_ok

# --- validate_auth tests ---

test_auth_none() { unset ANTHROPIC_API_KEY CLAUDE_CODE_USE_VERTEX; validate_auth; }
expect_failure_output "validate_auth: no auth" "No Claude authentication" test_auth_none

test_auth_api_key() { ANTHROPIC_API_KEY=sk-test; validate_auth; }
expect_success "validate_auth: api key" test_auth_api_key

test_auth_vertex() { unset ANTHROPIC_API_KEY; CLAUDE_CODE_USE_VERTEX=1; ANTHROPIC_VERTEX_PROJECT_ID=proj; CLOUD_ML_REGION=us-east5; validate_auth; }
expect_success "validate_auth: vertex" test_auth_vertex

test_auth_vertex_missing() { unset ANTHROPIC_API_KEY ANTHROPIC_VERTEX_PROJECT_ID; CLAUDE_CODE_USE_VERTEX=1; CLOUD_ML_REGION=us-east5; validate_auth; }
expect_failure_output "validate_auth: vertex missing project" "ANTHROPIC_VERTEX_PROJECT_ID" test_auth_vertex_missing

# --- build_prompt tests ---

TMPDIR_TEST=$(mktemp -d)
AUTOSOLVE_TMPDIR=$(mktemp -d)
export AUTOSOLVE_TMPDIR
trap 'rm -rf "$TMPDIR_TEST" "$AUTOSOLVE_TMPDIR"' EXIT

echo "This is skill content" > "$TMPDIR_TEST/skill.md"

test_build_prompt_only() {
  GITHUB_OUTPUT=$(mktemp)
  INPUT_PROMPT='Fix the bug'; INPUT_SKILL=; INPUT_ADDITIONAL_INSTRUCTIONS=
  INPUT_FOOTER_TYPE=implementation; INPUT_BLOCKED_PATHS='.github/workflows/'
  build_prompt
  check_contains 'Fix the bug' "$PROMPT_FILE"
}
expect_success "build_prompt: prompt only" test_build_prompt_only

test_build_preamble() {
  GITHUB_OUTPUT=$(mktemp)
  INPUT_PROMPT='Fix bug'; INPUT_SKILL=; INPUT_ADDITIONAL_INSTRUCTIONS=
  INPUT_FOOTER_TYPE=implementation; INPUT_BLOCKED_PATHS='.github/workflows/'
  build_prompt
  check_contains 'system_instruction' "$PROMPT_FILE"
}
expect_success "build_prompt: contains security preamble" test_build_preamble

test_build_blocked() {
  GITHUB_OUTPUT=$(mktemp)
  INPUT_PROMPT='Fix bug'; INPUT_SKILL=; INPUT_ADDITIONAL_INSTRUCTIONS=
  INPUT_FOOTER_TYPE=implementation; INPUT_BLOCKED_PATHS='.github/workflows/,secrets/'
  build_prompt
  check_contains 'secrets/' "$PROMPT_FILE"
}
expect_success "build_prompt: contains blocked paths" test_build_blocked

test_build_skill() {
  GITHUB_OUTPUT=$(mktemp)
  INPUT_PROMPT=; INPUT_SKILL="$TMPDIR_TEST/skill.md"; INPUT_ADDITIONAL_INSTRUCTIONS=
  INPUT_FOOTER_TYPE=implementation; INPUT_BLOCKED_PATHS='.github/workflows/'
  build_prompt
  check_contains 'This is skill content' "$PROMPT_FILE"
}
expect_success "build_prompt: skill file" test_build_skill

test_build_missing_skill() {
  GITHUB_OUTPUT=$(mktemp)
  INPUT_PROMPT=; INPUT_SKILL='/nonexistent/skill.md'; INPUT_ADDITIONAL_INSTRUCTIONS=
  INPUT_FOOTER_TYPE=implementation; INPUT_BLOCKED_PATHS='.github/workflows/'
  build_prompt
}
expect_failure_output "build_prompt: missing skill file" "Skill file not found" test_build_missing_skill

test_build_assessment_footer() {
  GITHUB_OUTPUT=$(mktemp)
  INPUT_PROMPT='Assess this'; INPUT_SKILL=; INPUT_ADDITIONAL_INSTRUCTIONS=
  INPUT_FOOTER_TYPE=assessment; INPUT_ASSESSMENT_CRITERIA=; INPUT_BLOCKED_PATHS='.github/workflows/'
  build_prompt
  check_contains 'ASSESSMENT_RESULT' "$PROMPT_FILE"
}
expect_success "build_prompt: assessment footer" test_build_assessment_footer

test_build_custom_criteria() {
  GITHUB_OUTPUT=$(mktemp)
  INPUT_PROMPT='Assess this'; INPUT_SKILL=; INPUT_ADDITIONAL_INSTRUCTIONS=
  INPUT_FOOTER_TYPE=assessment; INPUT_ASSESSMENT_CRITERIA='Only proceed if trivial'; INPUT_BLOCKED_PATHS='.github/workflows/'
  build_prompt
  check_contains 'Only proceed if trivial' "$PROMPT_FILE"
}
expect_success "build_prompt: custom assessment criteria" test_build_custom_criteria

test_build_additional() {
  GITHUB_OUTPUT=$(mktemp)
  INPUT_PROMPT='Fix bug'; INPUT_SKILL=; INPUT_ADDITIONAL_INSTRUCTIONS='Do not run tests'
  INPUT_FOOTER_TYPE=implementation; INPUT_BLOCKED_PATHS='.github/workflows/'
  build_prompt
  check_contains 'Do not run tests' "$PROMPT_FILE"
}
expect_success "build_prompt: additional instructions" test_build_additional

# --- extract_result tests ---

RESULT_DIR="$TMPDIR_TEST/results"
mkdir -p "$RESULT_DIR"

test_extract_proceed() {
  echo '{"type":"result","result":"ASSESSMENT_RESULT - PROCEED","session_id":"abc123"}' > "$RESULT_DIR/proceed.json"
  extract_result "$RESULT_DIR/proceed.json" "ASSESSMENT_RESULT" | check_contains "ASSESSMENT_RESULT - PROCEED"
}
expect_success "extract_result: PROCEED" test_extract_proceed

test_extract_skip() {
  echo '{"type":"result","result":"ASSESSMENT_RESULT - SKIP","session_id":"abc123"}' > "$RESULT_DIR/skip.json"
  extract_result "$RESULT_DIR/skip.json" "ASSESSMENT_RESULT" | check_contains "ASSESSMENT_RESULT - SKIP"
}
expect_success "extract_result: SKIP" test_extract_skip

test_extract_success() {
  echo '{"type":"result","result":"IMPLEMENTATION_RESULT - SUCCESS","session_id":"abc123"}' > "$RESULT_DIR/success.json"
  extract_result "$RESULT_DIR/success.json" "IMPLEMENTATION_RESULT" | check_contains "IMPLEMENTATION_RESULT - SUCCESS"
}
expect_success "extract_result: SUCCESS" test_extract_success

test_extract_no_marker() {
  echo '{"type":"result","result":"I did some stuff but forgot the marker","session_id":"abc123"}' > "$RESULT_DIR/no_marker.json"
  extract_result "$RESULT_DIR/no_marker.json" "ASSESSMENT_RESULT"
}
expect_failure "extract_result: no marker" test_extract_no_marker

test_extract_missing() { extract_result "/nonexistent.json" "ASSESSMENT_RESULT"; }
expect_failure "extract_result: missing file" test_extract_missing

# --- extract_session_id tests ---

test_session_id() {
  echo '{"type":"result","result":"ASSESSMENT_RESULT - PROCEED","session_id":"abc123"}' > "$RESULT_DIR/session.json"
  extract_session_id "$RESULT_DIR/session.json" | check_contains "abc123"
}
expect_success "extract_session_id: valid" test_session_id

print_results
