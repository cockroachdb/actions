#!/usr/bin/env bash
# Assessment functions for claude-autosolve.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../actions_helpers.sh
source ./shared.sh

run_assessment() {
  require_command claude
  local prompt_file="${PROMPT_FILE:?PROMPT_FILE must be set}"
  local model="${INPUT_MODEL:?INPUT_MODEL must be set}"
  local output_file="$AUTOSOLVE_TMPDIR/assessment.json"

  log_info "Running assessment with model: $model"

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
  # extract_result returns non-zero when the marker isn't found; prevent
  # set -e from exiting so we can handle missing results below.
  result_text="$(extract_result "$output_file" "ASSESSMENT_RESULT")" || true

  if [ -z "$result_text" ]; then
    log_error "No assessment result found in Claude output"
    set_output "assessment" "ERROR"
    return 1
  fi

  # Log the full assessment result so it appears in the action run logs.
  log_info "$result_text"

  if echo "$result_text" | grep --quiet "ASSESSMENT_RESULT - PROCEED"; then
    log_notice "Assessment: PROCEED"
    set_output "assessment" "PROCEED"
  elif echo "$result_text" | grep --quiet "ASSESSMENT_RESULT - SKIP"; then
    log_notice "Assessment: SKIP"
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
  summary="$(truncate_output 200 "$(echo "$result_text" | sed '/^ASSESSMENT_RESULT/d')")"

  set_output "assessment" "$assessment"
  set_output_multiline "summary" "$summary"
  set_output_multiline "result" "$result_text"

  write_step_summary <<EOF
## Autosolve Assessment
**Result:** $assessment
$([ -n "$summary" ] && printf '### Summary\n%s' "$summary")
EOF
}
