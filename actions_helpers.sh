#!/usr/bin/env bash
# Shared shell helpers for all GitHub Actions in this repo.

# GitHub Actions log commands — emit structured annotations via stdout.
log_error()   { echo "::error::$*"; }
log_warning() { echo "::warning::$*"; }
log_notice()  { echo "::notice::$*"; }

# Write a single-line output: set_output key value
set_output() {
  echo "$1=$2" >> "${GITHUB_OUTPUT:-/dev/null}"
}

# Write a multiline output: set_output_multiline key value
set_output_multiline() {
  local delim
  delim="GHEOF_$$_$(date +%s)"
  {
    echo "$1<<$delim"
    echo "$2"
    echo "$delim"
  } >> "${GITHUB_OUTPUT:-/dev/null}"
}

# Verify a command is on PATH: require_command <name>
require_command() {
  command -v "$1" >/dev/null || { log_error "$1 not found on PATH"; return 1; }
}

# Append content to the GitHub Actions step summary.
# Usage: write_step_summary <<EOF ... EOF
write_step_summary() {
  cat >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# Get the base branch for a PR, using provided value or falling back to repo default.
# Usage: base_branch=$(get_base_branch "$provided_branch" "$repo")
get_base_branch() {
  local provided_branch="$1"
  local repo="$2"

  if [ -n "$provided_branch" ]; then
    echo "$provided_branch"
  else
    local default_branch
    default_branch=$(gh repo view "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name')
    # jq outputs "null" as a string when defaultBranchRef is null (empty repo)
    if [ -z "$default_branch" ] || [ "$default_branch" = "null" ]; then
      default_branch="main"
    fi
    echo "$default_branch"
  fi
}

# Assert that input contains a given substring.
# Usage: check_contains "expected" "$file"   (reads file)
#        cmd | check_contains "expected"     (reads stdin)
check_contains() {
  if [ $# -ge 2 ]; then
    grep --quiet --fixed-strings -- "$1" "$2"
  else
    grep --quiet --fixed-strings -- "$1"
  fi
}

# Assert that input matches a given regex pattern.
# Usage: check_contains_pattern "^prefix" "$file"   (reads file)
#        cmd | check_contains_pattern "^prefix"      (reads stdin)
check_contains_pattern() {
  if [ $# -ge 2 ]; then
    grep --quiet -- "$1" "$2"
  else
    grep --quiet -- "$1"
  fi
}
