#!/usr/bin/env bash
# Assessment functions for claude-autosolve.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../actions_helpers.sh
source ./shared.sh

run_assessment() {
  command -v claude >/dev/null || { log_error "claude CLI not found on PATH"; return 1; }
  local prompt_file="${PROMPT_FILE:?PROMPT_FILE must be set}"
  local model="${INPUT_MODEL:-claude-opus-4-6}"
  local output_file="$AUTOSOLVE_TMPDIR/assessment.json"

  echo "Running assessment with model: $model"

  local exit_code=0
  claude --print \
    --model "$model" \
    --allowedTools "Read,Grep,Glob" \
    --output-format json \
    --max-turns 30 \
    < "$prompt_file" > "$output_file" || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    log_warning "Claude CLI exited with code $exit_code"
  fi

  local result_text
  result_text="$(extract_result "$output_file" "ASSESSMENT_RESULT")" || true

  if [ -z "$result_text" ]; then
    log_error "No assessment result found in Claude output"
    set_output "assessment" "ERROR"
    return 1
  fi

  if echo "$result_text" | grep --quiet "ASSESSMENT_RESULT - PROCEED"; then
    echo "Assessment: PROCEED"
    set_output "assessment" "PROCEED"
  elif echo "$result_text" | grep --quiet "ASSESSMENT_RESULT - SKIP"; then
    echo "Assessment: SKIP"
    set_output "assessment" "SKIP"
  else
    log_error "Assessment result did not contain a valid PROCEED or SKIP marker"
    set_output "assessment" "ERROR"
    return 1
  fi

  # Store result text for summary extraction
  echo "$result_text" > "$AUTOSOLVE_TMPDIR/assessment_result.txt"
}

set_assess_outputs() {
  local assessment="${ASSESS_RESULT:-ERROR}"
  local result_text=""
  if [ -f "$AUTOSOLVE_TMPDIR/assessment_result.txt" ]; then
    result_text="$(cat "$AUTOSOLVE_TMPDIR/assessment_result.txt")"
  fi

  # Extract summary: everything before the ASSESSMENT_RESULT line
  local summary
  summary="$(echo "$result_text" | sed '/^ASSESSMENT_RESULT/d' | head -50)"

  set_output "assessment" "$assessment"
  set_output_multiline "summary" "$summary"
  set_output_multiline "result" "$result_text"

  {
    echo "## Autosolve Assessment"
    echo "**Result:** $assessment"
    if [ -n "$summary" ]; then
      echo "### Summary"
      echo "$summary"
    fi
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}
