#!/usr/bin/env bash
# Tests for resolve_ref.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$PWD"
source ../test_helpers.sh

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

export GITHUB_OUTPUT="$TMPDIR/github_output.txt"

reset_output() {
  : > "$GITHUB_OUTPUT"
}

get_ref() {
  grep "ref=" "$GITHUB_OUTPUT" | cut -d= -f2
}

# Helper: create a caller workflow file with the given uses line.
make_workflow() {
  local path="$TMPDIR/$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
name: Caller
on: workflow_dispatch
jobs:
  call:
    uses: $2
EOF
}

# =============================================
# Basic ref resolution
# =============================================

reset_output
test_basic_tag_ref() {
  make_workflow ".github/workflows/caller.yml" \
    "cockroachdb/actions/.github/workflows/autosolve.yml@v1.2.3"
  env WORKFLOW_REF="myorg/myrepo/.github/workflows/caller.yml@refs/heads/main" \
      REPO="myorg/myrepo" \
      REF="refs/heads/main" \
      WORKFLOW_NAME="autosolve.yml" \
      "$SCRIPT_DIR/resolve_ref.sh"
  [ "$(get_ref)" = "v1.2.3" ]
}
expect_success "basic: resolves tag ref" test_basic_tag_ref

reset_output
test_basic_branch_ref() {
  make_workflow ".github/workflows/caller.yml" \
    "cockroachdb/actions/.github/workflows/autosolve.yml@main"
  env WORKFLOW_REF="myorg/myrepo/.github/workflows/caller.yml@refs/heads/main" \
      REPO="myorg/myrepo" \
      REF="refs/heads/main" \
      WORKFLOW_NAME="autosolve.yml" \
      "$SCRIPT_DIR/resolve_ref.sh"
  [ "$(get_ref)" = "main" ]
}
expect_success "basic: resolves branch ref" test_basic_branch_ref

reset_output
test_basic_sha_ref() {
  make_workflow ".github/workflows/caller.yml" \
    "cockroachdb/actions/.github/workflows/autosolve.yml@abc123def456"
  env WORKFLOW_REF="myorg/myrepo/.github/workflows/caller.yml@refs/heads/main" \
      REPO="myorg/myrepo" \
      REF="refs/heads/main" \
      WORKFLOW_NAME="autosolve.yml" \
      "$SCRIPT_DIR/resolve_ref.sh"
  [ "$(get_ref)" = "abc123def456" ]
}
expect_success "basic: resolves SHA ref" test_basic_sha_ref

reset_output
test_slash_branch_ref() {
  make_workflow ".github/workflows/caller.yml" \
    "cockroachdb/actions/.github/workflows/autosolve.yml@pr/autosolve-workflow"
  env WORKFLOW_REF="myorg/myrepo/.github/workflows/caller.yml@refs/heads/main" \
      REPO="myorg/myrepo" \
      REF="refs/heads/main" \
      WORKFLOW_NAME="autosolve.yml" \
      "$SCRIPT_DIR/resolve_ref.sh"
  [ "$(get_ref)" = "pr/autosolve-workflow" ]
}
expect_success "basic: resolves slash-branch ref" test_slash_branch_ref

# =============================================
# Local ./ reference
# =============================================

reset_output
test_local_ref() {
  make_workflow ".github/workflows/caller.yml" \
    "./.github/workflows/autosolve.yml"
  env WORKFLOW_REF="myorg/myrepo/.github/workflows/caller.yml@refs/heads/main" \
      REPO="myorg/myrepo" \
      REF="refs/heads/main" \
      WORKFLOW_NAME="autosolve.yml" \
      "$SCRIPT_DIR/resolve_ref.sh"
  [ "$(get_ref)" = "refs/heads/main" ]
}
expect_success "local: ./ reference uses caller ref" test_local_ref

# =============================================
# Bug: pull_request event — github.ref != workflow_ref suffix
#
# On pull_request, github.ref is refs/pull/42/merge but
# github.workflow_ref ends with @refs/heads/main.
# The current code strips "@${REF}" which won't match,
# leaving the @refs/heads/main suffix in the path.
# =============================================

reset_output
test_pr_event_ref_mismatch() {
  make_workflow ".github/workflows/caller.yml" \
    "cockroachdb/actions/.github/workflows/autosolve.yml@v2.0.0"
  env WORKFLOW_REF="myorg/myrepo/.github/workflows/caller.yml@refs/heads/main" \
      REPO="myorg/myrepo" \
      REF="refs/pull/42/merge" \
      WORKFLOW_NAME="autosolve.yml" \
      "$SCRIPT_DIR/resolve_ref.sh"
  [ "$(get_ref)" = "v2.0.0" ]
}
expect_success "pr event: ref mismatch between github.ref and workflow_ref" test_pr_event_ref_mismatch

# =============================================
# Bug: grep treats workflow_name as regex
#
# "autosolve.yml" as regex: the dot matches any char, so it
# matches "autosolvexyml". With fixed-string grep it should NOT
# match, and the script should fail.
# =============================================

reset_output
test_grep_regex_false_positive() {
  local path="$TMPDIR/.github/workflows/caller.yml"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
name: Caller
on: workflow_dispatch
jobs:
  call:
    uses: cockroachdb/actions/.github/workflows/autosolvexyml@v1.0.0
EOF
  env WORKFLOW_REF="myorg/myrepo/.github/workflows/caller.yml@refs/heads/main" \
      REPO="myorg/myrepo" \
      REF="refs/heads/main" \
      WORKFLOW_NAME="autosolve.yml" \
      "$SCRIPT_DIR/resolve_ref.sh"
}
expect_failure "grep regex: dot in name should not match arbitrary char" test_grep_regex_false_positive

# =============================================
# Only match uses: lines, not comments or job names
# =============================================

reset_output
test_ignores_comments_and_job_names() {
  local path="$TMPDIR/.github/workflows/caller.yml"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
name: Caller
on: workflow_dispatch
jobs:
  # This job calls autosolve.yml to fix issues
  autosolve.yml-runner:
    uses: cockroachdb/actions/.github/workflows/autosolve.yml@v3.0.0
EOF
  env WORKFLOW_REF="myorg/myrepo/.github/workflows/caller.yml@refs/heads/main" \
      REPO="myorg/myrepo" \
      REF="refs/heads/main" \
      WORKFLOW_NAME="autosolve.yml" \
      "$SCRIPT_DIR/resolve_ref.sh"
  [ "$(get_ref)" = "v3.0.0" ]
}
expect_success "uses-only: ignores comments and job names, matches uses: line" test_ignores_comments_and_job_names

# =============================================
# Error cases
# =============================================

reset_output
test_missing_workflow_file() {
  env WORKFLOW_REF="myorg/myrepo/.github/workflows/nonexistent.yml@refs/heads/main" \
      REPO="myorg/myrepo" \
      REF="refs/heads/main" \
      WORKFLOW_NAME="autosolve.yml" \
      "$SCRIPT_DIR/resolve_ref.sh"
}
expect_failure "error: missing workflow file" "Could not find caller workflow" test_missing_workflow_file

reset_output
test_workflow_name_not_found() {
  make_workflow ".github/workflows/caller.yml" \
    "cockroachdb/actions/.github/workflows/other.yml@v1.0.0"
  env WORKFLOW_REF="myorg/myrepo/.github/workflows/caller.yml@refs/heads/main" \
      REPO="myorg/myrepo" \
      REF="refs/heads/main" \
      WORKFLOW_NAME="nonexistent-workflow.yml" \
      "$SCRIPT_DIR/resolve_ref.sh"
}
expect_failure "error: workflow name not found" "Could not find 'nonexistent-workflow.yml'" test_workflow_name_not_found

print_results
