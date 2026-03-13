#!/usr/bin/env bash
# Jira integration functions for claude-autosolve.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../actions_helpers.sh
source ./shared.sh

build_jira_prompt() {
  local prompt="${INPUT_PROMPT:-}"
  local title="${TICKET_TITLE:-}"
  local desc="${TICKET_DESC:-}"
  local ac="${TICKET_AC:-}"
  local ticket_id="${TICKET_ID:-}"

  if [ -n "$prompt" ]; then
    # User provided an explicit prompt override, use it
    set_output "prompt" "$prompt"
    return 0
  fi

  # Build prompt from Jira ticket fields
  local built_prompt
  built_prompt="$(cat <<EOF
Fix the following Jira ticket:

Ticket: ${ticket_id}
Title: ${title}
Description:
${desc}
EOF
)"

  if [ -n "$ac" ]; then
    built_prompt="$(cat <<EOF
${built_prompt}

Acceptance Criteria:
${ac}
EOF
)"
  fi

  set_output_multiline "prompt" "$built_prompt"
}

post_comment() {
  local jira_token="${JIRA_TOKEN:?JIRA_TOKEN is required}"
  local jira_base_url="${JIRA_BASE_URL:?JIRA_BASE_URL is required}"
  local ticket_id="${TICKET_ID:?TICKET_ID is required}"
  local comment_type="${COMMENT_TYPE:-result}"

  local body
  if [ "$comment_type" = "assessment" ]; then
    local assessment="${ASSESSMENT:-}"
    local summary="${SUMMARY:-}"
    if [ "$assessment" = "PROCEED" ]; then
      body="*Autosolve Assessment*: PROCEED\n\nAssessment passed. Attempting automated fix..."
    else
      body="*Autosolve Assessment*: SKIP\n\n${summary}"
    fi
  else
    local status="${STATUS:-FAILED}"
    local summary="${SUMMARY:-}"
    local pr_url="${PR_URL:-}"
    if [ "$status" = "SUCCESS" ] && [ -n "$pr_url" ]; then
      body="*Autosolve Result*: SUCCESS\n\nPR created: ${pr_url}\n\nPlease review the changes carefully before approving.\n\n${summary}"
    else
      body="*Autosolve Result*: FAILED\n\nAutomatic implementation was unable to complete the task. Manual intervention may be needed.\n\n${summary}"
    fi
  fi

  # Post comment to Jira
  local comment_payload
  comment_payload="$(jq --null-input --arg body "$body" '{body: $body}')"

  local http_code
  http_code="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Basic ${jira_token}" \
    --header "Content-Type: application/json" \
    --data "$comment_payload" \
    "${jira_base_url}/rest/api/2/issue/${ticket_id}/comment")"

  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    echo "Jira comment posted successfully"
    set_output "posted" "true"
  else
    log_warning "Failed to post Jira comment (HTTP $http_code)"
    set_output "posted" "false"
  fi
}

transition_ticket() {
  local jira_token="${JIRA_TOKEN:?JIRA_TOKEN is required}"
  local jira_base_url="${JIRA_BASE_URL:?JIRA_BASE_URL is required}"
  local ticket_id="${TICKET_ID:?TICKET_ID is required}"
  local assessment="${ASSESSMENT:-}"
  local impl_status="${IMPL_STATUS:-}"
  local transition_on_pr="${TRANSITION_ON_PR:-}"
  local transition_on_skip="${TRANSITION_ON_SKIP:-}"

  local transition_name=""
  if [ "$impl_status" = "SUCCESS" ] && [ -n "$transition_on_pr" ]; then
    transition_name="$transition_on_pr"
  elif [ "$assessment" = "SKIP" ] && [ -n "$transition_on_skip" ]; then
    transition_name="$transition_on_skip"
  fi

  if [ -z "$transition_name" ]; then
    echo "No Jira transition to apply"
    return 0
  fi

  # Get available transitions
  local transitions_response
  transitions_response="$(curl --silent \
    --header "Authorization: Basic ${jira_token}" \
    --header "Content-Type: application/json" \
    "${jira_base_url}/rest/api/2/issue/${ticket_id}/transitions")"

  local transition_id
  transition_id="$(echo "$transitions_response" | jq --raw-output --arg name "$transition_name" \
    '.transitions[] | select(.name == $name) | .id')" || true

  if [ -z "$transition_id" ]; then
    log_warning "Jira transition '$transition_name' not found for ticket $ticket_id"
    return 0
  fi

  local http_code
  http_code="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Basic ${jira_token}" \
    --header "Content-Type: application/json" \
    --data "{\"transition\":{\"id\":\"${transition_id}\"}}" \
    "${jira_base_url}/rest/api/2/issue/${ticket_id}/transitions")"

  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    echo "Jira ticket transitioned to '$transition_name'"
  else
    log_warning "Failed to transition Jira ticket (HTTP $http_code)"
  fi
}
