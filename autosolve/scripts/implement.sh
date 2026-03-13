#!/usr/bin/env bash
# Implementation functions for claude-autosolve.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../actions_helpers.sh
source ./shared.sh

run_implementation() {
  command -v claude >/dev/null || { log_error "claude CLI not found on PATH"; return 1; }
  local prompt_file="${PROMPT_FILE:?PROMPT_FILE must be set}"
  local model="${INPUT_MODEL:-claude-opus-4-6}"
  local allowed_tools="${INPUT_ALLOWED_TOOLS:-Read,Write,Edit,Grep,Glob,Bash(git add:*),Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(git show:*)}"
  local max_retries="${INPUT_MAX_RETRIES:-3}"
  local output_file="$AUTOSOLVE_TMPDIR/implementation.json"

  echo "Running implementation with model: $model (max retries: $max_retries)"

  local attempt=1
  local session_id=""
  local implementation_status="FAILED"

  while [ "$attempt" -le "$max_retries" ]; do
    echo "--- Attempt $attempt of $max_retries ---"

    local exit_code=0
    if [ "$attempt" -eq 1 ]; then
      claude --print \
        --model "$model" \
        --allowedTools "$allowed_tools" \
        --output-format json \
        --max-turns 200 \
        < "$prompt_file" > "$output_file" || exit_code=$?
    else
      local retry_prompt
      retry_prompt="The previous attempt did not succeed. Please review what went wrong, try a different approach if needed, and attempt the fix again. Remember to end your response with IMPLEMENTATION_RESULT - SUCCESS or IMPLEMENTATION_RESULT - FAILED."

      local resume_args=()
      if [ -n "$session_id" ]; then
        resume_args=(--resume "$session_id")
      fi

      echo "$retry_prompt" | claude --print \
        --model "$model" \
        --allowedTools "$allowed_tools" \
        --output-format json \
        --max-turns 200 \
        "${resume_args[@]}" \
        > "$output_file" || exit_code=$?
    fi

    if [ "$exit_code" -ne 0 ]; then
      log_warning "Claude CLI exited with code $exit_code on attempt $attempt"
    fi

    local result_text
    result_text="$(extract_result "$output_file" "IMPLEMENTATION_RESULT")" || true

    # Extract session ID for potential retry
    session_id="$(extract_session_id "$output_file")"

    if echo "$result_text" | grep --quiet "IMPLEMENTATION_RESULT - SUCCESS"; then
      echo "Implementation succeeded on attempt $attempt"
      implementation_status="SUCCESS"
      echo "$result_text" > "$AUTOSOLVE_TMPDIR/implementation_result.txt"
      break
    fi

    echo "Attempt $attempt did not succeed"
    if [ -n "$result_text" ]; then
      echo "$result_text" > "$AUTOSOLVE_TMPDIR/implementation_result.txt"
    fi

    if [ "$attempt" -lt "$max_retries" ]; then
      echo "Waiting 10 seconds before retry..."
      sleep 10
    fi

    attempt=$((attempt + 1))
  done

  set_output "implementation" "$implementation_status"
}

security_check() {
  local blocked_paths="${INPUT_BLOCKED_PATHS:-.github/workflows/}"

  IFS=',' read -ra BLOCKED_PATHS <<< "$blocked_paths"
  # Trim whitespace from each path
  for i in "${!BLOCKED_PATHS[@]}"; do
    BLOCKED_PATHS[$i]="$(echo "${BLOCKED_PATHS[$i]}" | xargs)"
  done

  echo "Checking for modifications to blocked paths: ${BLOCKED_PATHS[*]}"

  local violation_found=false

  # Collect all changed file lists once
  local unstaged staged untracked
  unstaged="$(git diff --name-only)"
  staged="$(git diff --name-only --cached)"
  untracked="$(git ls-files --others --exclude-standard)"
  local all_changed
  all_changed="$(printf '%s\n%s\n%s\n' "$unstaged" "$staged" "$untracked" | sort -u)"

  for blocked in "${BLOCKED_PATHS[@]}"; do
    [ -z "$blocked" ] && continue

    # Use -F for literal prefix matching (not regex)
    if echo "$unstaged" | grep --quiet --ignore-case --fixed-strings "$blocked"; then
      log_error "Blocked path modified (unstaged): $blocked"
      violation_found=true
    fi

    if echo "$untracked" | grep --quiet --ignore-case --fixed-strings "$blocked"; then
      log_error "Blocked path has new untracked file: $blocked"
      violation_found=true
    fi

    if echo "$staged" | grep --quiet --ignore-case --fixed-strings "$blocked"; then
      log_error "Blocked path modified (staged): $blocked"
      violation_found=true
    fi
  done

  # Check for symlinks to blocked paths across all changed files
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ -L "$f" ]; then
      local target
      target=$(readlink -f "$f")
      for blocked in "${BLOCKED_PATHS[@]}"; do
        [ -z "$blocked" ] && continue
        if echo "$target" | grep --quiet --ignore-case --fixed-strings "/$blocked"; then
          log_error "Symlink to blocked path: $f -> $target"
          violation_found=true
        fi
      done
    fi
  done <<< "$all_changed"

  if [ "$violation_found" = true ]; then
    log_error "Security check failed: blocked paths were modified"
    git reset HEAD
    return 1
  fi

  echo "Security check passed"
}

push_and_pr() {
  local fork_owner="${INPUT_FORK_OWNER:?fork_owner is required}"
  local fork_repo="${INPUT_FORK_REPO:?fork_repo is required}"
  local fork_push_token="${INPUT_FORK_PUSH_TOKEN:?fork_push_token is required}"
  local pr_create_token="${INPUT_PR_CREATE_TOKEN:?pr_create_token is required}"
  local pr_base_branch="${INPUT_PR_BASE_BRANCH:-}"
  local pr_labels="${INPUT_PR_LABELS:-autosolve}"
  local pr_draft="${INPUT_PR_DRAFT:-true}"
  local pr_title="${INPUT_PR_TITLE:-}"
  local pr_body_template="${INPUT_PR_BODY_TEMPLATE:-}"
  local git_user_name="${INPUT_GIT_USER_NAME:-autosolve[bot]}"
  local git_user_email="${INPUT_GIT_USER_EMAIL:-autosolve[bot]@users.noreply.github.com}"
  local branch_suffix="${INPUT_BRANCH_SUFFIX:-}"

  # Default base branch to repo default
  if [ -z "$pr_base_branch" ]; then
    local ref
    ref="$(git symbolic-ref refs/remotes/origin/HEAD)" || ref="refs/remotes/origin/main"
    pr_base_branch="${ref#refs/remotes/origin/}"
  fi

  # Configure git identity
  git config user.name "$git_user_name"
  git config user.email "$git_user_email"

  # Configure fork remote with credential helper
  git config --local credential.helper \
    "!f() { echo \"username=${fork_owner}\"; echo \"password=${fork_push_token}\"; }; f"
  local fork_url="https://github.com/${fork_owner}/${fork_repo}.git"
  if git remote | grep --quiet --fixed-strings "fork"; then
    git remote set-url fork "$fork_url"
  else
    git remote add fork "$fork_url"
  fi

  # Create branch
  if [ -z "$branch_suffix" ]; then
    branch_suffix="$(date +%Y%m%d-%H%M%S)"
  fi
  local branch_name="autosolve/${branch_suffix}"
  git checkout -b "$branch_name"

  # Read and remove Claude-generated metadata files before staging
  local claude_commit_message=""
  if [ -f ".autosolve-commit-message" ]; then
    claude_commit_message="$(head -1 .autosolve-commit-message)"
    rm -f .autosolve-commit-message
  fi
  if [ -f ".autosolve-pr-body" ]; then
    cp .autosolve-pr-body "$AUTOSOLVE_TMPDIR/autosolve-pr-body"
    rm -f .autosolve-pr-body
  fi

  # Stage tracked file modifications as safety net
  git add --update

  # Re-run security check on final staged changeset
  security_check

  # Verify there are staged changes
  if git diff --quiet --cached; then
    log_error "No changes to commit"
    return 1
  fi

  # Build commit message — prefer pr_title, then Claude's summary, then prompt
  local commit_subject
  if [ -n "$pr_title" ]; then
    commit_subject="$pr_title"
  elif [ -n "$claude_commit_message" ]; then
    commit_subject="$claude_commit_message"
  else
    commit_subject="autosolve: $(echo "${INPUT_PROMPT:-automated change}" | head -c 72)"
  fi

  git commit --message "$(cat <<EOF
${commit_subject}

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

  # Push to fork
  git push --set-upstream fork "$branch_name" --force

  # Build PR body: prefer Claude-written .autosolve-pr-body, then custom
  # template, then fall back to the commit message body.
  local pr_body
  if [ -n "$pr_body_template" ]; then
    pr_body="$pr_body_template"
    # Support template variables
    local summary=""
    if [ -f "$AUTOSOLVE_TMPDIR/implementation_result.txt" ]; then
      summary="$(sed '/^IMPLEMENTATION_RESULT/d' "$AUTOSOLVE_TMPDIR/implementation_result.txt" | head -50)"
    fi
    pr_body="${pr_body//\{\{SUMMARY\}\}/$summary}"
    pr_body="${pr_body//\{\{BRANCH\}\}/$branch_name}"
  elif [ -f "$AUTOSOLVE_TMPDIR/autosolve-pr-body" ]; then
    pr_body="$(cat "$AUTOSOLVE_TMPDIR/autosolve-pr-body")"
  else
    # Fall back to commit message body (everything after the first line)
    pr_body="$(git log -1 --format='%b')"
  fi

  # Append auto-generation notice
  pr_body="$(cat <<EOF
${pr_body}

---

*This PR was auto-generated by [claude-autosolve-action](https://github.com/cockroachdb/actions) using Claude Code.*
*Please review carefully before approving.*
EOF
)"

  # Build PR title
  if [ -z "$pr_title" ]; then
    pr_title="$(git log -1 --format='%s')"
  fi

  # Create PR
  local draft_flag=""
  if [ "$pr_draft" = "true" ]; then
    draft_flag="--draft"
  fi

  # Ensure all PR labels exist on the repo (gh pr create fails if they don't)
  local label
  while IFS= read -r label; do
    label="$(echo "$label" | xargs)"
    [ -z "$label" ] && continue
    GH_TOKEN="${pr_create_token}" gh label create "$label" \
      --repo "${GITHUB_REPOSITORY:-}" \
      --color "6f42c1" 2>&1 || true
  done <<< "${pr_labels//,/$'\n'}"

  local pr_url
  pr_url="$(GH_TOKEN="${pr_create_token}" gh pr create \
    --repo "${GITHUB_REPOSITORY:-}" \
    --head "${fork_owner}:${branch_name}" \
    --base "${pr_base_branch}" \
    $draft_flag \
    --title "$pr_title" \
    --body "$pr_body" \
    --label "$pr_labels" 2>&1)" || {
    log_error "Failed to create PR: $pr_url"
    return 1
  }

  echo "PR created: $pr_url"
  set_output "pr_url" "$pr_url"
  set_output "branch_name" "$branch_name"
}

set_implement_outputs() {
  local impl_result="${IMPL_RESULT:-FAILED}"
  local security_conclusion="${SECURITY_CONCLUSION:-}"
  local pr_conclusion="${PR_CONCLUSION:-}"
  local create_pr="${INPUT_CREATE_PR:-true}"
  local pr_url="${PR_URL:-}"
  local branch_name="${BRANCH_NAME:-}"

  local status
  if [ "$impl_result" = "SUCCESS" ] && [ "$security_conclusion" != "failure" ]; then
    # When PR creation is enabled, the PR step must also succeed
    if [ "$create_pr" = "true" ] && [ "$pr_conclusion" != "success" ]; then
      status="FAILED"
    else
      status="SUCCESS"
    fi
  else
    status="FAILED"
  fi

  local result_text=""
  if [ -f "$AUTOSOLVE_TMPDIR/implementation_result.txt" ]; then
    result_text="$(cat "$AUTOSOLVE_TMPDIR/implementation_result.txt")"
  fi

  local summary
  summary="$(echo "$result_text" | sed '/^IMPLEMENTATION_RESULT/d' | head -50)"

  set_output "status" "$status"
  set_output "pr_url" "$pr_url"
  set_output "branch_name" "$branch_name"
  set_output_multiline "summary" "$summary"
  set_output_multiline "result" "$result_text"

  {
    echo "## Autosolve Implementation"
    echo "**Status:** $status"
    if [ -n "$pr_url" ]; then
      echo "**PR:** $pr_url"
    fi
    if [ -n "$branch_name" ]; then
      echo "**Branch:** \`$branch_name\`"
    fi
    if [ -n "$summary" ]; then
      echo "### Summary"
      echo "$summary"
    fi
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

cleanup_implement() {
  # These may not exist if the step that set them was skipped; || true to avoid failing cleanup.
  git config --local --unset credential.helper || true
  git remote remove fork || true
  rm -rf "${AUTOSOLVE_TMPDIR:-}"
}
