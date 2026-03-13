#!/usr/bin/env bash
# Tests for jira.sh functions (non-HTTP functions only).
# shellcheck disable=SC2034  # Variables are read by sourced functions
set -euo pipefail
trap 'echo "Error occurred at line $LINENO"; exit 1' ERR

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../test_helpers.sh
source ../../actions_helpers.sh
source ./shared.sh
source ./jira.sh

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# --- build_jira_prompt tests ---

test_prompt_override() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_override"
  touch "$GITHUB_OUTPUT"
  INPUT_PROMPT='Custom prompt'; TICKET_TITLE='ignored'; TICKET_DESC='ignored'
  TICKET_AC='ignored'; TICKET_ID='PROJ-1'
  build_jira_prompt
  grep -q 'prompt=Custom prompt' "$GITHUB_OUTPUT"
}
expect_success "build_jira_prompt: explicit prompt override" test_prompt_override

test_prompt_from_ticket() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_ticket"
  touch "$GITHUB_OUTPUT"
  INPUT_PROMPT=''; TICKET_TITLE='Fix login bug'; TICKET_DESC='Users cannot log in'
  TICKET_AC=''; TICKET_ID='PROJ-42'
  build_jira_prompt
  grep -q 'PROJ-42' "$GITHUB_OUTPUT" && grep -q 'Fix login bug' "$GITHUB_OUTPUT"
}
expect_success "build_jira_prompt: builds from ticket fields" test_prompt_from_ticket

test_prompt_with_ac() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_ac"
  touch "$GITHUB_OUTPUT"
  INPUT_PROMPT=''; TICKET_TITLE='Fix bug'; TICKET_DESC='Something broke'
  TICKET_AC='Login should work'; TICKET_ID='PROJ-99'
  build_jira_prompt
  grep -q 'Acceptance Criteria' "$GITHUB_OUTPUT" && grep -q 'Login should work' "$GITHUB_OUTPUT"
}
expect_success "build_jira_prompt: includes acceptance criteria" test_prompt_with_ac

test_prompt_without_ac() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_no_ac"
  touch "$GITHUB_OUTPUT"
  INPUT_PROMPT=''; TICKET_TITLE='Fix bug'; TICKET_DESC='Something broke'
  TICKET_AC=''; TICKET_ID='PROJ-100'
  build_jira_prompt
  ! grep -q 'Acceptance Criteria' "$GITHUB_OUTPUT"
}
expect_success "build_jira_prompt: omits AC when empty" test_prompt_without_ac

# --- set_final_status tests ---

test_status_skipped() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_skipped"
  touch "$GITHUB_OUTPUT"
  ASSESSMENT=SKIP; IMPL_STATUS=''
  set_final_status
  grep -q 'status=SKIPPED' "$GITHUB_OUTPUT"
}
expect_success "set_final_status: SKIP -> SKIPPED" test_status_skipped

test_status_success() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_success"
  touch "$GITHUB_OUTPUT"
  ASSESSMENT=PROCEED; IMPL_STATUS=SUCCESS
  set_final_status
  grep -q 'status=SUCCESS' "$GITHUB_OUTPUT"
}
expect_success "set_final_status: PROCEED + SUCCESS -> SUCCESS" test_status_success

test_status_failed() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_failed"
  touch "$GITHUB_OUTPUT"
  ASSESSMENT=PROCEED; IMPL_STATUS=FAILED
  set_final_status
  grep -q 'status=FAILED' "$GITHUB_OUTPUT"
}
expect_success "set_final_status: PROCEED + FAILED -> FAILED" test_status_failed

test_status_failed_no_impl() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_failed2"
  touch "$GITHUB_OUTPUT"
  ASSESSMENT=PROCEED; IMPL_STATUS=''
  set_final_status
  grep -q 'status=FAILED' "$GITHUB_OUTPUT"
}
expect_success "set_final_status: PROCEED + no impl -> FAILED" test_status_failed_no_impl

print_results
