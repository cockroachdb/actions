#!/usr/bin/env bash
# Shared shell helpers for all GitHub Actions in this repo.

# GitHub Actions log commands — emit structured annotations via stdout.
log_error()   { echo "::error::$*"; }
log_warning() { echo "::warning::$*"; }
log_notice()  { echo "::notice::$*"; }
# Plain informational output — no GitHub annotation, just step log output.
# Use for multi-line diagnostic data where ::notice:: would be inappropriate.
log_info()    { echo "$*"; }

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

# Truncate text to a maximum number of lines, appending a notice if truncated.
# Usage: truncate_output <max_lines> <text>
truncate_output() {
  local max_lines="$1"
  local text="$2"
  local line_count
  line_count="$(echo "$text" | wc -l | tr -d ' ')"
  if [ "$line_count" -gt "$max_lines" ]; then
    echo "$text" | head -"$max_lines"
    echo "[... truncated ($line_count lines total, showing first $max_lines)]"
  else
    echo "$text"
  fi
}

# Append content to the GitHub Actions step summary.
# Usage: write_step_summary <<EOF ... EOF
write_step_summary() {
  cat >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}
