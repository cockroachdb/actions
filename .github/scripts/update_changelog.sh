#!/usr/bin/env bash
set -euo pipefail

# Updates CHANGELOG.md by inserting a new version header under [Unreleased].
#
# Usage: update-changelog.sh
#
# Environment variables:
#   VERSION      - Version being released (e.g., "1.2.3")
#   RELEASE_DATE - Release date in YYYY-MM-DD format (defaults to current date)

# Save current directory (where CHANGELOG.md is expected)
WORK_DIR="$(pwd)"

# Change to script directory for relative sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source ../../actions_helpers.sh

version="$VERSION"

# Validate semver format
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  log_error "Version must be in semver format (e.g., 1.2.3), got: $version"
  exit 1
fi

release_date="${RELEASE_DATE:-$(date +%Y-%m-%d)}"

# Validate date format if provided
if [ -n "${RELEASE_DATE:-}" ] && ! [[ "$release_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  log_error "RELEASE_DATE must be in YYYY-MM-DD format, got: $release_date"
  exit 1
fi

# Go back to work directory where CHANGELOG.md is
cd "$WORK_DIR"

# Insert new version header under [Unreleased] header
awk -v version="$version" -v date="$release_date" '
/^## \[Unreleased\]/ {
    print
    print ""
    print "## [" version "] - " date
    next
}
{ print }
' CHANGELOG.md > CHANGELOG.md.tmp

# Validate the transformation succeeded
if [ ! -s CHANGELOG.md.tmp ]; then
  log_error "Failed to update CHANGELOG.md - transformation produced empty output"
  rm -f CHANGELOG.md.tmp
  exit 1
fi

# Verify the version header was actually inserted
if ! check_contains "## [$version]" CHANGELOG.md.tmp; then
  log_error "Version header '## [$version]' not found in transformed changelog"
  rm -f CHANGELOG.md.tmp
  exit 1
fi

mv CHANGELOG.md.tmp CHANGELOG.md

log_notice "Updated CHANGELOG.md with version $version dated $release_date"
