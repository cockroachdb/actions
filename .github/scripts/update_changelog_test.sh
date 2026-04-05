#!/usr/bin/env bash
# Tests for update-changelog.sh
set -euo pipefail
trap 'echo "Error occurred at line $LINENO"; exit 1' ERR

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../test_helpers.sh
source ../../actions_helpers.sh

# Set up temporary directory for test outputs
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Test helper: wraps update-changelog.sh for use with expect_diff
# Takes original content as third argument, outputs transformed content
test_update_changelog() {
  local version="$1"
  local release_date="$2"
  local original_content="$3"

  # Create test directory
  local test_dir="${TMPDIR_TEST}/test_$(date +%s%N)"
  mkdir -p "$test_dir"

  # Write original content to CHANGELOG.md
  echo "$original_content" > "$test_dir/CHANGELOG.md"

  # Run script from test directory with env vars
  (
    cd "$test_dir"
    export VERSION="$version"
    export RELEASE_DATE="$release_date"
    bash "${OLDPWD}/update_changelog.sh" >/dev/null
    cat CHANGELOG.md
  )
}

# =============================================
# Basic functionality tests
# =============================================

test_custom_release_date() {
  local original="# Changelog

## [Unreleased]

### Added
- Holiday release

## [1.4.0] - 2025-11-01

### Added
- Previous feature"

  expect_diff "inserts version header with custom date" \
    "$original" \
    "+## [1.5.0] - 2025-12-25" \
    test_update_changelog "1.5.0" "2025-12-25" "$original"
}
test_custom_release_date

test_default_release_date() {
  local today
  today=$(date +%Y-%m-%d)

  local original="# Changelog

## [Unreleased]

### Added
- Latest change"

  expect_diff "inserts version header with current date" \
    "$original" \
    "+## [3.0.0] - $today" \
    test_update_changelog "3.0.0" "" "$original"
}
test_default_release_date

# =============================================
# Edge cases
# =============================================

test_empty_unreleased_section() {
  # Note: Verification that the Unreleased section has content is done by earlier
  # steps in the workflow (release-version-extract) and does not fall under the
  # responsibility of this script. This test only verifies that the script handles
  # empty Unreleased sections gracefully if they do occur.
  local original="# Changelog

## [Unreleased]

## [1.0.0] - 2026-03-01

### Added
- First release"

  expect_diff "inserts version header for empty Unreleased section" \
    "$original" \
    "+## [1.1.0] - 2026-03-31" \
    test_update_changelog "1.1.0" "2026-03-31" "$original"
}
test_empty_unreleased_section

test_multiple_subsections() {
  local original="# Changelog

## [Unreleased]

### Added
- New API endpoint

### Changed
- Updated dependencies

### Fixed
- Bug fix

## [2.0.0] - 2026-02-01"

  expect_diff "preserves multiple subsections below version header" \
    "$original" \
    "+## [2.1.0] - 2026-03-31" \
    test_update_changelog "2.1.0" "2026-03-31" "$original"
}
test_multiple_subsections

# =============================================
# Error cases
# =============================================

test_missing_version_env_var() {
  local test_dir="${TMPDIR_TEST}/test_missing_version"
  mkdir -p "$test_dir"
  echo "# Changelog" > "$test_dir/CHANGELOG.md"

  # Should fail when VERSION env var not provided
  (
    cd "$test_dir"
    bash "${OLDPWD}/update_changelog.sh"
  )
}
expect_failure_output "fails when VERSION env var missing" "VERSION" test_missing_version_env_var

test_fails_on_empty_changelog() {
  local test_dir="${TMPDIR_TEST}/test_empty_changelog"
  mkdir -p "$test_dir"

  # Create empty CHANGELOG.md
  touch "$test_dir/CHANGELOG.md"

  # Should fail with error about empty output
  (
    cd "$test_dir"
    export VERSION="1.0.0"
    export RELEASE_DATE="2026-03-31"
    bash "${OLDPWD}/update_changelog.sh"
  )
}
expect_failure_output "fails when CHANGELOG transformation produces empty output" "transformation produced empty output" test_fails_on_empty_changelog

print_results
