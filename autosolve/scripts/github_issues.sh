#!/usr/bin/env bash
# GitHub Issues integration functions for claude-autosolve.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../actions_helpers.sh
source ./shared.sh

build_github_issue_prompt() {
  local prompt="${INPUT_PROMPT:-}"
  local issue_number="${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
  local issue_title="${ISSUE_TITLE:-}"
  local issue_body="${ISSUE_BODY:-}"

  if [ -n "$prompt" ]; then
    set_output_multiline "prompt" "$prompt"
    return 0
  fi

  local built_prompt
  built_prompt="$(cat <<EOF
Fix GitHub issue #${issue_number}.
Title: ${issue_title}
Body: ${issue_body}
EOF
)"

  set_output_multiline "prompt" "$built_prompt"
}

comment_on_issue() {
  local github_token="${GITHUB_TOKEN_INPUT:?GITHUB_TOKEN_INPUT is required}"
  local issue_number="${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
  local comment_type="${COMMENT_TYPE:?COMMENT_TYPE is required}"

  case "$comment_type" in
    skipped)
      local summary="${SUMMARY:-}"
      local sanitized
      sanitized="$(echo "$summary" | sed 's/<[^>]*>//g' | sed 's/```/` ` `/g')"
      local body
      body="$(cat <<EOF
Auto-solver assessed this issue but determined it is not suitable for automated resolution.

\`\`\`
${sanitized}
\`\`\`
EOF
)"
      GH_TOKEN="$github_token" gh issue comment "$issue_number" --repo "$GITHUB_REPOSITORY" --body "$body"
      ;;
    success)
      local pr_url="${PR_URL:?PR_URL is required for success comment}"
      GH_TOKEN="$github_token" gh issue comment "$issue_number" --repo "$GITHUB_REPOSITORY" --body \
        "Auto-solver has created a draft PR: ${pr_url}

Please review the changes carefully before approving."
      ;;
    failed)
      GH_TOKEN="$github_token" gh issue comment "$issue_number" --repo "$GITHUB_REPOSITORY" --body \
        "Auto-solver attempted to fix this issue but was unable to complete the implementation.

This issue may require human intervention."
      ;;
    *)
      log_error "Unknown comment type: $comment_type"
      return 1
      ;;
  esac
}

remove_label() {
  local github_token="${GITHUB_TOKEN_INPUT:?GITHUB_TOKEN_INPUT is required}"
  local issue_number="${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
  local trigger_label="${TRIGGER_LABEL:-autosolve}"

  GH_TOKEN="$github_token" gh issue edit "$issue_number" --repo "$GITHUB_REPOSITORY" --remove-label "$trigger_label" || true
}
