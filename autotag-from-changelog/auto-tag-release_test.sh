#!/usr/bin/env bash
# Tests for auto-tag-release.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(pwd)"
source ../test_helpers.sh

# Set up a temporary bare repo to act as "origin" and a working clone.
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

git config user.email >/dev/null || git config --global user.email "test@test.com"
git config user.name >/dev/null || git config --global user.name "test"
git init --bare --initial-branch=main "$TMPDIR/origin.git" >/dev/null
git clone "$TMPDIR/origin.git" "$TMPDIR/work" >/dev/null
cd "$TMPDIR/work"
git commit --allow-empty -m "initial" >/dev/null
git push origin main >/dev/null

# =============================================
# parse_changelog unit tests
# =============================================

# Source just the function from the script. We use a subshell trick:
# the script exits early because $changelog isn't set, so we extract
# the function definition directly.
eval "$(sed -n '/^parse_changelog()/,/^}/p' "$SCRIPT_DIR/auto-tag-release.sh")"

run_parse_test() {
  local name="$1"
  local expected_version="$2"
  local expected_has_unreleased="$3"  # "true" or "false"
  local changelog_file="$4"

  parse_changelog "$changelog_file"

  if [ "$version" != "$expected_version" ]; then
    echo "FAIL: $name — expected version '$expected_version', got '$version'"
    FAIL=$((FAIL + 1))
    return
  fi

  local has_unreleased="false"
  if [ -n "$unreleased_content" ]; then
    has_unreleased="true"
  fi

  if [ "$has_unreleased" != "$expected_has_unreleased" ]; then
    echo "FAIL: $name — expected unreleased_content=$expected_has_unreleased, got $has_unreleased"
    FAIL=$((FAIL + 1))
    return
  fi

  echo "PASS: $name"
  PASS=$((PASS + 1))
}

# parse_changelog: standard changelog with unreleased content
cat <<'EOF' > CHANGELOG.md
## [Unreleased]

### Added

- A new feature

## [1.2.3] - 2026-01-01
EOF
run_parse_test "parse: unreleased content with version" "1.2.3" "true" CHANGELOG.md

# parse_changelog: empty unreleased section
cat <<'EOF' > CHANGELOG.md
## [Unreleased]

## [3.0.0] - 2026-01-01
EOF
run_parse_test "parse: empty unreleased section" "3.0.0" "false" CHANGELOG.md

# parse_changelog: no version after unreleased
cat <<'EOF' > CHANGELOG.md
## [Unreleased]
EOF
run_parse_test "parse: no version after unreleased" "" "false" CHANGELOG.md

# parse_changelog: no unreleased section at all
cat <<'EOF' > CHANGELOG.md
## [2.0.0] - 2026-01-01
EOF
run_parse_test "parse: no unreleased section" "" "false" CHANGELOG.md

# parse_changelog: multiple versions, picks first
cat <<'EOF' > CHANGELOG.md
## [Unreleased]

## [2.1.0] - 2026-03-01

## [2.0.0] - 2026-01-01
EOF
run_parse_test "parse: multiple versions picks first" "2.1.0" "false" CHANGELOG.md

# parse_changelog: only blank lines under unreleased
cat <<'EOF' > CHANGELOG.md
## [Unreleased]



## [1.0.0] - 2026-01-01
EOF
run_parse_test "parse: only blank lines under unreleased" "1.0.0" "false" CHANGELOG.md

# parse_changelog: content before unreleased is ignored
cat <<'EOF' > CHANGELOG.md
# Changelog

Some preamble text.

## [Unreleased]

### Fixed

- A bug fix

## [0.9.0] - 2025-12-01
EOF
run_parse_test "parse: content before unreleased is ignored" "0.9.0" "true" CHANGELOG.md

# =============================================
# Integration tests
# =============================================

GITHUB_OUTPUT="$TMPDIR/github_output"
export GITHUB_OUTPUT

# --- Content under [Unreleased], previous version not tagged — should fail ---
cat <<'EOF' > CHANGELOG.md
## [Unreleased]

### Added

- A new feature

## [1.0.0] - 2026-01-01
EOF

expect_failure_output "content under [Unreleased], untagged version" "is not tagged" \
  env CHANGELOG_PATH=CHANGELOG.md "$SCRIPT_DIR/auto-tag-release.sh"

# --- Empty [Unreleased], new version, no existing tag — should tag ---
cat <<'EOF' > CHANGELOG.md
## [Unreleased]

## [1.0.0] - 2026-01-01
EOF

expect_success_output "creates new tag" "Tagged v1.0.0 successfully" \
  env CHANGELOG_PATH=CHANGELOG.md "$SCRIPT_DIR/auto-tag-release.sh"
expect_output "creates new tag — tag-created output" "tag-created" "true"
expect_output "creates new tag — tag output" "tag" "v1.0.0"

# Verify the tag was actually created
if git rev-parse v1.0.0 >/dev/null; then
  echo "PASS: tag v1.0.0 exists"
  PASS=$((PASS + 1))
else
  echo "FAIL: tag v1.0.0 was not created"
  FAIL=$((FAIL + 1))
fi

# --- Tag already exists — should skip ---
expect_success_output "tag already exists" "already exists" \
  env CHANGELOG_PATH=CHANGELOG.md "$SCRIPT_DIR/auto-tag-release.sh"
expect_output "tag already exists — tag-created output" "tag-created" "false"

# --- Content under [Unreleased], previous version already tagged — should pass ---
cat <<'EOF' > CHANGELOG.md
## [Unreleased]

### Added

- A new feature

## [1.0.0] - 2026-01-01
EOF

expect_success_output "content under [Unreleased], tagged version" "already tagged" \
  env CHANGELOG_PATH=CHANGELOG.md "$SCRIPT_DIR/auto-tag-release.sh"

# --- No version sections at all — should skip ---
cat <<'EOF' > CHANGELOG.md
## [Unreleased]
EOF

expect_success_output "no released version" "No released version found" \
  env CHANGELOG_PATH=CHANGELOG.md "$SCRIPT_DIR/auto-tag-release.sh"
expect_output "no released version — tag-created output" "tag-created" "false"

# --- No [Unreleased] section — should skip ---
cat <<'EOF' > CHANGELOG.md
## [2.0.0] - 2026-01-01
EOF

expect_success "no [Unreleased] section" \
  env CHANGELOG_PATH=CHANGELOG.md "$SCRIPT_DIR/auto-tag-release.sh"

# --- [Unreleased] with only blank lines (no content) — should tag ---
cat <<'EOF' > CHANGELOG.md
## [Unreleased]



## [2.0.0] - 2026-01-01
EOF

expect_success "blank lines under [Unreleased]" \
  env CHANGELOG_PATH=CHANGELOG.md "$SCRIPT_DIR/auto-tag-release.sh"

print_results
