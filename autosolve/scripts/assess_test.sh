#!/usr/bin/env bash
# Tests for assess.sh functions.
# shellcheck disable=SC2034  # Variables are read by sourced functions
set -euo pipefail
trap 'echo "Error occurred at line $LINENO"; exit 1' ERR

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../test_helpers.sh
source ../../actions_helpers.sh
source ./shared.sh
source ./assess.sh

TMPDIR_TEST=$(mktemp -d)
AUTOSOLVE_TMPDIR=$(mktemp -d)
export AUTOSOLVE_TMPDIR
trap 'rm -rf "$TMPDIR_TEST" "$AUTOSOLVE_TMPDIR"' EXIT

# --- set_assess_outputs tests ---

test_outputs_proceed() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_proceed"
  touch "$GITHUB_OUTPUT"
  printf 'The task is clear and bounded.\nASSESSMENT_RESULT - PROCEED\n' > "$AUTOSOLVE_TMPDIR/assessment_result.txt"
  ASSESS_RESULT=PROCEED
  set_assess_outputs
  grep -q 'assessment=PROCEED' "$GITHUB_OUTPUT"
}
expect_success "set_assess_outputs: PROCEED" test_outputs_proceed

test_outputs_skip() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_skip"
  touch "$GITHUB_OUTPUT"
  printf 'Too ambiguous for automation.\nASSESSMENT_RESULT - SKIP\n' > "$AUTOSOLVE_TMPDIR/assessment_result.txt"
  ASSESS_RESULT=SKIP
  set_assess_outputs
  grep -q 'assessment=SKIP' "$GITHUB_OUTPUT"
}
expect_success "set_assess_outputs: SKIP" test_outputs_skip

test_outputs_summary_strips_marker() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_summary"
  touch "$GITHUB_OUTPUT"
  printf 'This is the reasoning.\nASSESSMENT_RESULT - PROCEED\n' > "$AUTOSOLVE_TMPDIR/assessment_result.txt"
  ASSESS_RESULT=PROCEED
  set_assess_outputs
  # Extract just the summary block (between summary<<DELIM and DELIM) and verify marker is absent
  local summary
  summary=$(sed -n '/^summary<</,/^GHEOF_/p' "$GITHUB_OUTPUT")
  echo "$summary" | grep -q 'This is the reasoning' && ! echo "$summary" | grep -q 'ASSESSMENT_RESULT'
}
expect_success "set_assess_outputs: summary strips marker" test_outputs_summary_strips_marker

test_outputs_no_result_file() {
  GITHUB_OUTPUT="$TMPDIR_TEST/gh_out_none"
  touch "$GITHUB_OUTPUT"
  rm -f "$AUTOSOLVE_TMPDIR/assessment_result.txt"
  ASSESS_RESULT=ERROR
  set_assess_outputs
  grep -q 'assessment=ERROR' "$GITHUB_OUTPUT"
}
expect_success "set_assess_outputs: no result file" test_outputs_no_result_file

print_results
