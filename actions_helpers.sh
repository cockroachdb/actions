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
