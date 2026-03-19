#!/usr/bin/env bash
# Shared functions for claude-autosolve actions.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../actions_helpers.sh

ACTION_ROOT="${ACTION_ROOT:-$(cd ..; pwd)}"

validate_inputs() {
  if [ -z "${INPUT_PROMPT:-}" ] && [ -z "${INPUT_SKILL:-}" ]; then
    log_error "At least one of 'prompt' or 'skill' must be provided."
    return 1
  fi

  if [ "${INPUT_CREATE_PR:-}" = "true" ]; then
    local missing=()
    [ -z "${INPUT_FORK_OWNER:-}" ] && missing+=("fork_owner")
    [ -z "${INPUT_FORK_REPO:-}" ] && missing+=("fork_repo")
    [ -z "${INPUT_FORK_PUSH_TOKEN:-}" ] && missing+=("fork_push_token")
    [ -z "${INPUT_PR_CREATE_TOKEN:-}" ] && missing+=("pr_create_token")
    if [ "${#missing[@]}" -gt 0 ]; then
      log_error "When create_pr is true, the following inputs are required: ${missing[*]}"
      return 1
    fi
  fi
}

validate_auth() {
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    return 0
  fi

  if [ "${CLAUDE_CODE_USE_VERTEX:-}" = "1" ]; then
    local missing=()
    [ -z "${ANTHROPIC_VERTEX_PROJECT_ID:-}" ] && missing+=("ANTHROPIC_VERTEX_PROJECT_ID")
    [ -z "${CLOUD_ML_REGION:-}" ] && missing+=("CLOUD_ML_REGION")
    if [ "${#missing[@]}" -gt 0 ]; then
      log_error "Vertex AI auth requires: ${missing[*]}"
      return 1
    fi
    return 0
  fi

  log_error "No Claude authentication configured. Set ANTHROPIC_API_KEY or enable Vertex AI (CLAUDE_CODE_USE_VERTEX=1)."
  return 1
}

install_claude() {
  if command -v claude >/dev/null; then
    local installed_version
    installed_version="$(claude --version)"
    log_info "Claude CLI already installed: $installed_version"
    return 0
  fi
  local version="${CLAUDE_CLI_VERSION:?CLAUDE_CLI_VERSION must be set}"
  log_info "Installing Claude CLI v${version} via npm..."
  npm install --global "@anthropic-ai/claude-code@${version}"
  local installed_version
  installed_version="$(claude --version)"
  log_info "Claude CLI installed: $installed_version"
}

build_prompt() {
  local prompt_file
  prompt_file="$(mktemp "$AUTOSOLVE_TMPDIR/prompt_XXXXXX")"

  # Security preamble
  cat "$ACTION_ROOT/prompts/security-preamble.md" >> "$prompt_file"

  # Inject blocked paths
  local blocked_paths="${INPUT_BLOCKED_PATHS:-.github/workflows/}"
  printf '\nThe following paths are BLOCKED and must not be modified:\n' >> "$prompt_file"
  IFS=',' read -ra paths <<< "$blocked_paths"
  for p in "${paths[@]}"; do
    p="$(echo "$p" | xargs)" # trim whitespace
    [ -n "$p" ] && printf -- '- %s\n' "$p" >> "$prompt_file"
  done

  # Task section
  printf '\n<task>\n' >> "$prompt_file"

  if [ -n "${INPUT_PROMPT:-}" ]; then
    printf '%s\n' "$INPUT_PROMPT" >> "$prompt_file"
  fi

  if [ -n "${INPUT_SKILL:-}" ]; then
    if [ ! -f "$INPUT_SKILL" ]; then
      log_error "Skill file not found: $INPUT_SKILL"
      return 1
    fi
    cat "$INPUT_SKILL" >> "$prompt_file"
  fi

  if [ -n "${INPUT_ADDITIONAL_INSTRUCTIONS:-}" ]; then
    printf '\n%s\n' "$INPUT_ADDITIONAL_INSTRUCTIONS" >> "$prompt_file"
  fi

  printf '</task>\n\n' >> "$prompt_file"

  # Footer
  local footer_type="${INPUT_FOOTER_TYPE:-implementation}"
  if [ "$footer_type" = "assessment" ]; then
    local footer_content
    footer_content="$(cat "$ACTION_ROOT/prompts/assessment-footer.md")"

    local criteria
    if [ -n "${INPUT_ASSESSMENT_CRITERIA:-}" ]; then
      criteria="$INPUT_ASSESSMENT_CRITERIA"
    else
      criteria="$(cat <<'CRITERIA'
- PROCEED if: the task is clear, affects a bounded set of files, can be
  delivered as a single commit, and does not require architectural decisions
  or human judgment on product direction.
- SKIP if: the task is ambiguous, requires design decisions or RFC, affects
  many unrelated components, requires human judgment, or would benefit from
  being split into multiple commits (e.g., separate refactoring from
  behavioral changes, or independent fixes across unrelated subsystems).
CRITERIA
)"
    fi

    footer_content="${footer_content//\{\{ASSESSMENT_CRITERIA\}\}/$criteria}"
    printf '%s\n' "$footer_content" >> "$prompt_file"
  else
    cat "$ACTION_ROOT/prompts/implementation-footer.md" >> "$prompt_file"
  fi

  set_output "prompt_file" "$prompt_file"
  # Also export for use in same shell
  export PROMPT_FILE="$prompt_file"
}

extract_result() {
  local json_file="$1"
  local marker_prefix="$2"

  if [ ! -f "$json_file" ]; then
    echo ""
    return 1
  fi

  local result_text
  # jq returns non-zero when the select filter matches nothing (e.g., if the
  # JSON is truncated or has an unexpected schema). We handle empty results below.
  result_text="$(jq --raw-output 'select(.type == "result") | .result' "$json_file")" || true

  if [ -z "$result_text" ]; then
    echo ""
    return 1
  fi

  echo "$result_text"

  if echo "$result_text" | grep --quiet "${marker_prefix} - SUCCESS\|${marker_prefix} - PROCEED"; then
    return 0
  elif echo "$result_text" | grep --quiet "${marker_prefix} - FAILED\|${marker_prefix} - SKIP"; then
    return 0
  else
    return 1
  fi
}

extract_session_id() {
  local json_file="$1"
  # jq returns non-zero when the select filter matches nothing; return empty
  # string instead of failing so callers can check for a missing session ID.
  jq --raw-output 'select(.type == "result") | .session_id' "$json_file" || true
}

set_final_status() {
  local assessment="${ASSESSMENT:-}"
  local impl_status="${IMPL_STATUS:-}"

  local status
  if [ "$assessment" = "SKIP" ]; then
    status="SKIPPED"
  elif [ "$impl_status" = "SUCCESS" ]; then
    status="SUCCESS"
  else
    status="FAILED"
  fi

  set_output "status" "$status"
}
