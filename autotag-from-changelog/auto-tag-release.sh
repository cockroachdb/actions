#!/usr/bin/env bash
# Auto-tag releases based on CHANGELOG.md versions.
#
# When the latest released version in CHANGELOG.md (the first ## [x.y.z] after
# ## [Unreleased]) does not have a corresponding git tag, this script creates
# and pushes it.
#
# If there is content under [Unreleased], the script verifies that the latest
# released version is already tagged. If it is, this is normal development and
# the script exits cleanly. If it isn't, something went wrong (a release was
# not tagged) and the script fails.
set -euo pipefail

ORIG_DIR="$(pwd)"
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../actions_helpers.sh
cd "$ORIG_DIR"

changelog="${CHANGELOG_PATH:-CHANGELOG.md}"
# Default to "true" when unset; reject empty strings and invalid values.
# Using ${VAR+x} instead of [[ -v VAR ]] for bash 3.2 (macOS) compatibility.
if [[ "${CREATE_MAJOR_TAG+x}" != "x" ]]; then
  create_major_tag="true"
elif [[ -z "$CREATE_MAJOR_TAG" ]]; then
  log_error "Invalid value for create-major-tag: ''. Expected 'true' or 'false'."
  exit 1
else
  create_major_tag=$(echo "$CREATE_MAJOR_TAG" | tr '[:upper:]' '[:lower:]')
fi
if [[ "$create_major_tag" != "true" && "$create_major_tag" != "false" ]]; then
  log_error "Invalid value for create-major-tag: '${CREATE_MAJOR_TAG}'. Expected 'true' or 'false'."
  exit 1
fi

# Check that the changelog file exists and is readable.
if [ ! -r "$changelog" ]; then
  log_error "Changelog file '$changelog' does not exist or is not readable."
  exit 1
fi
# Parse the changelog to extract the unreleased content and latest version.
# Sets two global variables:
#   unreleased_content — non-blank text under ## [Unreleased] (empty if none)
#   version — the first x.y.z version after ## [Unreleased] (empty if none)
parse_changelog() {
  local file="$1"
  unreleased_content=""
  version=""
  local in_unreleased=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[Unreleased\] ]]; then
      in_unreleased=true
      continue
    fi
    if $in_unreleased && [[ "$line" =~ ^##\ \[([0-9]+\.[0-9]+\.[0-9]+)\] ]]; then
      version="${BASH_REMATCH[1]}"
      break
    fi
    if $in_unreleased && [[ "$line" =~ [^[:space:]] ]]; then
      unreleased_content+="$line"
    fi
  done < "$file"
}

parse_changelog "$changelog"

# Check if the version string is empty.
if [ -z "$version" ]; then
  echo "No released version found in CHANGELOG.md, skipping."
  set_output "tag_created" "false"
  exit 0
fi

tag="v${version}"

# Check if the tag already exists on the remote.
remote_output=$(git ls-remote --tags origin "refs/tags/${tag}")
tag_exists=false
# Check if the remote output is non-empty (tag was found).
if [ -n "$remote_output" ]; then
  tag_exists=true
fi

# Check if there is content under the [Unreleased] section.
if [ -n "$unreleased_content" ]; then
  # There is content under [Unreleased]. The previous release must already
  # be tagged — if it isn't, something went wrong.
  if [ "$tag_exists" = true ]; then
    echo "Content under [Unreleased] and ${tag} already tagged, nothing to do."
    set_output "tag_created" "false"
    exit 0
  else
    log_error "CHANGELOG.md has content under [Unreleased] but ${tag} is not tagged. Tag the previous release before adding new entries."
    exit 1
  fi
fi

if [ "$tag_exists" = true ]; then
  echo "Tag ${tag} already exists, nothing to do."
  set_output "tag_created" "false"
  exit 0
fi

echo "Creating tag ${tag}..."
git tag "$tag"
git push origin "$tag"
echo "Tagged ${tag} successfully."

# Extract major version from semver tag (e.g., v1.2.3 -> v1)
if [ "$create_major_tag" = "true" ] && [[ "$tag" =~ ^v([0-9]+)\.[0-9]+\.[0-9]+ ]]; then
  major_tag="v${BASH_REMATCH[1]}"
  log_notice "Updating major tag ${major_tag} to point to ${tag}"
  git tag --force "$major_tag"
  git push --force origin "$major_tag"
  log_notice "Updated ${major_tag} successfully"
fi
set_output "tag_created" "true"
set_output "tag" "$tag"
