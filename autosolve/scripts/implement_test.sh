#!/usr/bin/env bash
# Tests for implement.sh functions (security_check).
# shellcheck disable=SC2034  # Variables are read by sourced functions
set -euo pipefail
trap 'echo "Error occurred at line $LINENO"; exit 1' ERR

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../test_helpers.sh
source ../../actions_helpers.sh
source ./shared.sh
source ./implement.sh

# Set up a temporary git repo for security_check tests
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

git config user.email >/dev/null 2>&1 || git config --global user.email "test@test.com"
git config user.name >/dev/null 2>&1 || git config --global user.name "test"

git init "$TMPDIR_TEST/repo" >/dev/null 2>&1
cd "$TMPDIR_TEST/repo"
git commit --allow-empty -m "initial" >/dev/null 2>&1

# --- security_check: no violations ---

mkdir -p src
echo "safe code" > src/main.go
git add src/main.go
git commit -m "add safe file" >/dev/null 2>&1

echo "modified" >> src/main.go
git add src/main.go

test_clean_pass() { INPUT_BLOCKED_PATHS='.github/workflows/'; security_check; }
expect_success "security_check: clean pass" test_clean_pass

# --- security_check: staged blocked path ---

git reset HEAD >/dev/null 2>&1
git checkout -- . 2>/dev/null || true

mkdir -p .github/workflows
echo "malicious" > .github/workflows/hack.yml
git add .github/workflows/hack.yml

test_blocked_staged() { INPUT_BLOCKED_PATHS='.github/workflows/'; security_check; }
expect_failure "security_check: blocked staged file" "Blocked path modified" test_blocked_staged

git reset HEAD >/dev/null 2>&1
rm -rf .github/workflows/hack.yml

# --- security_check: untracked blocked path ---

mkdir -p .github/workflows
echo "sneaky" > .github/workflows/sneaky.yml

test_blocked_untracked() { INPUT_BLOCKED_PATHS='.github/workflows/'; security_check; }
expect_failure "security_check: blocked untracked file" "Blocked path" test_blocked_untracked

rm -rf .github/workflows/sneaky.yml

# --- security_check: multiple blocked paths ---

mkdir -p secrets
echo "secret" > secrets/key.txt
git add secrets/key.txt

test_multiple_blocked() { INPUT_BLOCKED_PATHS='.github/workflows/,secrets/'; security_check; }
expect_failure "security_check: multiple blocked paths" "Blocked path" test_multiple_blocked

git reset HEAD >/dev/null 2>&1
rm -rf secrets

# --- set_implement_outputs tests ---

AUTOSOLVE_TMPDIR="$(mktemp -d)"
GITHUB_OUTPUT="$AUTOSOLVE_TMPDIR/github_output"

test_outputs_success() {
  > "$GITHUB_OUTPUT"
  IMPL_RESULT=SUCCESS SECURITY_CONCLUSION=success PR_CONCLUSION=success INPUT_CREATE_PR=true \
    PR_URL="https://example.com/pr/1" BRANCH_NAME="autosolve/test" set_implement_outputs
  grep --quiet "status=SUCCESS" "$GITHUB_OUTPUT"
}
expect_success "set_implement_outputs: full success" test_outputs_success

test_outputs_pr_failed() {
  > "$GITHUB_OUTPUT"
  IMPL_RESULT=SUCCESS SECURITY_CONCLUSION=success PR_CONCLUSION=failure INPUT_CREATE_PR=true \
    PR_URL="" BRANCH_NAME="" set_implement_outputs
  grep --quiet "status=FAILED" "$GITHUB_OUTPUT"
}
expect_success "set_implement_outputs: pr failure -> FAILED" test_outputs_pr_failed

test_outputs_no_pr() {
  > "$GITHUB_OUTPUT"
  IMPL_RESULT=SUCCESS SECURITY_CONCLUSION=success PR_CONCLUSION="" INPUT_CREATE_PR=false \
    PR_URL="" BRANCH_NAME="" set_implement_outputs
  grep --quiet "status=SUCCESS" "$GITHUB_OUTPUT"
}
expect_success "set_implement_outputs: create_pr=false -> SUCCESS" test_outputs_no_pr

test_outputs_impl_failed() {
  > "$GITHUB_OUTPUT"
  IMPL_RESULT=FAILED SECURITY_CONCLUSION="" PR_CONCLUSION="" INPUT_CREATE_PR=true \
    PR_URL="" BRANCH_NAME="" set_implement_outputs
  grep --quiet "status=FAILED" "$GITHUB_OUTPUT"
}
expect_success "set_implement_outputs: impl failed -> FAILED" test_outputs_impl_failed

rm -rf "$AUTOSOLVE_TMPDIR"

print_results
