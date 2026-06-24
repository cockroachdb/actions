#!/usr/bin/env bash
# Tests for parse-repositories.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$PWD"
source ../test_helpers.sh

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export GITHUB_OUTPUT="$TMPDIR/github_output.txt"

reset_output() {
  : > "$GITHUB_OUTPUT"
}

run_parse() {
  env REPOSITORIES="$1" "$SCRIPT_DIR/parse-repositories.sh"
}

# =============================================
# Basic grouping
# =============================================

reset_output
expect_success "basic: groups a single cockroachlabs repo" \
  run_parse "cockroachlabs/repo-a"
expect_step_output "basic: cockroachlabs output" "cockroachlabs" "repo-a"
expect_step_output "basic: cockroachdb output empty" "cockroachdb" ""

reset_output
expect_success "basic: groups both orgs" \
  run_parse "cockroachlabs/repo-a,cockroachdb/repo-b"
expect_step_output "basic: cockroachlabs grouped" "cockroachlabs" "repo-a"
expect_step_output "basic: cockroachdb grouped" "cockroachdb" "repo-b"

reset_output
expect_success "basic: multiple repos in one org are comma-joined" \
  run_parse "cockroachlabs/repo-a,cockroachlabs/repo-b"
expect_step_output "basic: cockroachlabs comma-joined" "cockroachlabs" "repo-a,repo-b"

# =============================================
# Comma and/or newline separation
# =============================================

reset_output
expect_success "split: newline-separated entries" \
  run_parse $'cockroachlabs/repo-a\ncockroachdb/repo-b'
expect_step_output "split: newline cockroachlabs" "cockroachlabs" "repo-a"
expect_step_output "split: newline cockroachdb" "cockroachdb" "repo-b"

reset_output
expect_success "split: mixed comma and newline" \
  run_parse $'cockroachlabs/repo-a,cockroachlabs/repo-b\ncockroachdb/repo-c'
expect_step_output "split: mixed cockroachlabs" "cockroachlabs" "repo-a,repo-b"
expect_step_output "split: mixed cockroachdb" "cockroachdb" "repo-c"

# =============================================
# Whitespace trimming and blank entries
# =============================================

reset_output
expect_success "trim: surrounding whitespace is stripped" \
  run_parse $'  cockroachlabs/repo-a  ,\tcockroachdb/repo-b\t'
expect_step_output "trim: cockroachlabs trimmed" "cockroachlabs" "repo-a"
expect_step_output "trim: cockroachdb trimmed" "cockroachdb" "repo-b"

reset_output
expect_success "trim: blank entries between separators are ignored" \
  run_parse $'cockroachlabs/repo-a,\n,\ncockroachdb/repo-b'
expect_step_output "trim: skips blanks cockroachlabs" "cockroachlabs" "repo-a"
expect_step_output "trim: skips blanks cockroachdb" "cockroachdb" "repo-b"

# =============================================
# Validation errors
# =============================================

reset_output
expect_failure_output "error: rejects entry without owner/repo separator" \
  "expected 'owner/repo'" \
  run_parse "cockroachlabs"

reset_output
expect_failure_output "error: rejects entry with empty repo" \
  "expected 'owner/repo'" \
  run_parse "cockroachlabs/"

reset_output
expect_failure_output "error: rejects entry with empty owner" \
  "expected 'owner/repo'" \
  run_parse "/repo-a"

reset_output
expect_failure_output "error: rejects entry with extra path segment" \
  "expected 'owner/repo'" \
  run_parse "cockroachlabs/repo-a/extra"

reset_output
expect_failure_output "error: rejects unsupported org" \
  "Unsupported org 'evilcorp'" \
  run_parse "evilcorp/repo-a"

# A valid entry alongside an unsupported one still fails.
reset_output
expect_failure_output "error: one bad org fails the whole parse" \
  "Unsupported org 'evilcorp'" \
  run_parse "cockroachlabs/repo-a,evilcorp/repo-b"

print_results
