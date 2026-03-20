#!/usr/bin/env bash
# Implementation functions for claude-autosolve.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../../actions_helpers.sh
source ./shared.sh

run_implementation() {
  require_command claude
  local prompt_file="${PROMPT_FILE:?PROMPT_FILE must be set}"
  local model="${INPUT_MODEL:?INPUT_MODEL must be set}"
  local allowed_tools="${INPUT_ALLOWED_TOOLS:-Read,Write,Edit,Grep,Glob,Bash(git add:*),Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(go build:*),Bash(go test:*),Bash(go vet:*),Bash(make:*)}"
  local max_retries="${INPUT_MAX_RETRIES:-3}"
  local output_file="$AUTOSOLVE_TMPDIR/implementation.json"

  # Ensure we're on the default branch so the PR diff is clean.
  ensure_default_branch

  # Warn if repo is missing recommended .gitignore patterns
  check_security_gitignore

  log_info "Running implementation with model: $model (max retries: $max_retries)"

  local attempt=1
  local session_id=""
  local implementation_status="FAILED"

  while [ "$attempt" -le "$max_retries" ]; do
    log_info "--- Attempt $attempt of $max_retries ---"

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
    # extract_result returns non-zero when the marker isn't found; prevent
    # set -e from exiting so we can handle missing results below.
    result_text="$(extract_result "$output_file" "IMPLEMENTATION_RESULT")" || true

    # Log Claude's result for debuggability
    if [ -n "$result_text" ]; then
      log_info "Claude result (attempt $attempt):"
      log_info "$result_text"
    else
      log_warning "No result text extracted from Claude output on attempt $attempt"
      # Log raw output to help debug unexpected output formats
      if [ -f "$output_file" ]; then
        log_warning "Could not extract result from Claude output on attempt $attempt — check step logs for raw output"
        log_info "$(cat "$output_file")"
      fi
    fi

    # Extract session ID for potential retry
    session_id="$(extract_session_id "$output_file")"

    if echo "$result_text" | grep --quiet "IMPLEMENTATION_RESULT - SUCCESS"; then
      log_notice "Implementation succeeded on attempt $attempt"
      implementation_status="SUCCESS"
      echo "$result_text" > "$AUTOSOLVE_TMPDIR/implementation_result.txt"
      break
    fi

    log_warning "Attempt $attempt did not succeed"
    if [ -n "$result_text" ]; then
      echo "$result_text" > "$AUTOSOLVE_TMPDIR/implementation_result.txt"
    fi

    if [ "$attempt" -lt "$max_retries" ]; then
      log_info "Waiting 10 seconds before retry..."
      sleep 10
    fi

    attempt=$((attempt + 1))
  done

  set_output "implementation" "$implementation_status"
}

ai_security_review() {
  log_info "Running AI security review on staged changes..."

  local diff
  diff="$(git diff --cached)" || { log_warning "Could not get staged diff, skipping AI review"; return 0; }
  [ -z "$diff" ] && return 0

  # Truncate very large diffs
  if [ "${#diff}" -gt 100000 ]; then
    diff="${diff:0:100000}
... (truncated)"
  fi

  local prompt_file="$AUTOSOLVE_TMPDIR/security_review_prompt.txt"
  local output_file="$AUTOSOLVE_TMPDIR/security_review.json"

  cat > "$prompt_file" <<SECEOF
You are a security reviewer. Your ONLY task is to review the following
git diff for sensitive content that should NOT be committed to a repository.

Look for:
- Credentials, API keys, tokens, passwords (hardcoded or in config)
- Private keys, certificates, keystores
- Cloud provider credential files (e.g., gha-creds-*.json, service account keys)
- .env files or environment variable files containing secrets
- Database connection strings with embedded passwords
- Any other secrets or sensitive data

Here is the staged diff:

${diff}

**OUTPUT REQUIREMENT**: End your response with exactly one of:
SECURITY_REVIEW - SUCCESS (if no sensitive content found)
SECURITY_REVIEW - FAILED (if any sensitive content found)

If you find sensitive content, list each finding before the FAIL marker.
SECEOF

  local exit_code=0
  claude --print \
    --model haiku \
    --output-format json \
    --max-turns 1 \
    < "$prompt_file" > "$output_file" 2>/dev/null || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    log_warning "AI security review failed to run, skipping"
    return 0
  fi

  local result_text
  result_text="$(jq -r 'select(.type == "result") | .result // empty' "$output_file" 2>/dev/null || true)"

  if [ -z "$result_text" ]; then
    log_warning "AI security review did not produce a result, skipping"
    return 0
  fi

  if echo "$result_text" | grep --quiet --fixed-strings "SECURITY_REVIEW - FAIL"; then
    log_error "AI security review found sensitive content:"
    log_error "$result_text"
    git reset HEAD
    return 1
  fi

  log_notice "AI security review passed"
}

ensure_default_branch() {
  local default_branch=""

  # Try git symbolic-ref first
  local default_ref
  if default_ref="$(git symbolic-ref refs/remotes/origin/HEAD 2>&1)"; then
    default_branch="${default_ref#refs/remotes/origin/}"
  else
    # Fall back to GitHub API
    log_info "refs/remotes/origin/HEAD not set, querying GitHub API for default branch"
    local repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
    if default_branch="$(gh repo view "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>&1)"; then
      : # success
    else
      log_warning "Could not determine default branch: git symbolic-ref failed and GitHub API failed ($default_branch)"
      return 1
    fi
  fi

  local current_ref
  if ! current_ref="$(git symbolic-ref HEAD 2>&1)"; then
    log_warning "HEAD is detached, cannot determine current branch"
    return 0
  fi
  local current_branch="${current_ref#refs/heads/}"

  if [ "$current_branch" != "$default_branch" ]; then
    log_info "Switching from $current_branch to default branch $default_branch"
    git checkout "$default_branch"
  fi
}

# Warn if the repo's .gitignore is missing recommended credential exclusion
# patterns. Does not modify the file — repo owners should add them.
check_security_gitignore() {
  local patterns="gha-creds-*.json *.pem *.key *.p12 *.pfx *.keystore credentials.json service-account*.json"
  if [ ! -f .gitignore ]; then
    log_warning "No .gitignore found. For defense-in-depth, add one with credential exclusion patterns: $patterns"
    return 0
  fi
  local missing=""
  for p in $patterns; do
    if ! grep --quiet --fixed-strings "$p" .gitignore; then
      missing="$missing $p"
    fi
  done
  if [ -n "$missing" ]; then
    log_warning "Repo .gitignore is missing recommended credential exclusion patterns:$missing"
  fi
}

security_check() {
  local blocked_paths="${INPUT_BLOCKED_PATHS:-.github/workflows/}"

  IFS=',' read -ra BLOCKED_PATHS <<< "$blocked_paths"
  # Trim whitespace from each path
  for i in "${!BLOCKED_PATHS[@]}"; do
    BLOCKED_PATHS[$i]="$(echo "${BLOCKED_PATHS[$i]}" | xargs)"
  done

  log_info "Checking for modifications to blocked paths: ${BLOCKED_PATHS[*]}"

  local violation_found=false

  # Collect all changed file lists once
  local unstaged staged untracked
  unstaged="$(git diff --name-only)"
  staged="$(git diff --name-only --cached)"
  untracked="$(git ls-files --others --exclude-standard)"
  local all_changed
  all_changed="$(printf '%s\n%s\n%s\n' "$unstaged" "$staged" "$untracked" | sort -u)"

  # Check each changed file against blocked path prefixes and sensitive patterns
  local file
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    for blocked in "${BLOCKED_PATHS[@]}"; do
      [ -z "$blocked" ] && continue
      # True prefix match using shell pattern
      case "$file" in
        "$blocked"*)
          log_error "Blocked path modified: $file (matches prefix $blocked)"
          violation_found=true
          ;;
      esac
    done
    # Check for sensitive files (credentials, keys, secrets)
    local basename
    basename="$(basename "$file")"
    local lower_basename
    lower_basename="$(echo "$basename" | tr '[:upper:]' '[:lower:]')"
    case "$lower_basename" in
      gha-creds-*|credentials.json|service-account*|.env|.env.*)
        log_error "Sensitive file detected: $file"
        violation_found=true
        ;;
    esac
    case "$file" in
      *.pem|*.key|*.p12|*.pfx|*.keystore)
        log_error "Sensitive file detected: $file (sensitive extension)"
        violation_found=true
        ;;
    esac
    # Check symlinks pointing into blocked paths
    if [ -L "$file" ]; then
      local target
      target=$(readlink -f "$file")
      for blocked in "${BLOCKED_PATHS[@]}"; do
        [ -z "$blocked" ] && continue
        case "$target" in
          */"$blocked"*)
            log_error "Symlink to blocked path: $file -> $target"
            violation_found=true
            ;;
        esac
      done
    fi
  done <<< "$all_changed"

  if [ "$violation_found" = true ]; then
    log_error "Security check failed: blocked paths were modified"
    git reset HEAD
    return 1
  fi

  log_notice "Security check passed"
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

  # Read and remove Claude-generated metadata files before staging.
  # .autosolve-commit-message: commit message (subject + body) written by Claude.
  # .autosolve-pr-body: full PR description written by Claude.
  local claude_commit_subject=""
  local claude_commit_body=""
  if [ -f ".autosolve-commit-message" ]; then
    claude_commit_subject="$(head -1 .autosolve-commit-message)"
    # Body is everything after the first blank line (skip subject + blank line)
    claude_commit_body="$(tail -n +3 .autosolve-commit-message)"
    rm -f .autosolve-commit-message
  fi
  if [ -f ".autosolve-pr-body" ]; then
    cp .autosolve-pr-body "$AUTOSOLVE_TMPDIR/autosolve-pr-body"
    rm -f .autosolve-pr-body
  fi

  # Stage only files that appear in the working tree diff. This avoids
  # blindly staging credential files or other artifacts dropped by action
  # steps (e.g., gha-creds-*.json).
  local changed_files
  changed_files="$(printf '%s\n%s\n%s\n' \
    "$(git diff --name-only)" \
    "$(git diff --name-only --cached)" \
    "$(git ls-files --others --exclude-standard)" | sort -u)"
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    git add "$f" || log_warning "Failed to stage $f"
  done <<< "$changed_files"

  # Re-run security check on final staged changeset
  security_check

  # Verify there are staged changes
  if git diff --quiet --cached; then
    log_error "No changes to commit"
    return 1
  fi

  # AI security review: have Claude scan the staged diff for sensitive content
  ai_security_review

  # Build commit message — prefer pr_title, then Claude's subject, then prompt
  local commit_subject
  if [ -n "$pr_title" ]; then
    commit_subject="$pr_title"
  elif [ -n "$claude_commit_subject" ]; then
    commit_subject="$claude_commit_subject"
  else
    commit_subject="autosolve: $(echo "${INPUT_PROMPT:-automated change}" | head -c 72)"
  fi

  local commit_body="${claude_commit_body:-}"

  git commit --message "$(cat <<EOF
${commit_subject}
$([ -n "$commit_body" ] && printf '\n%s' "$commit_body")

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

  # Force push to the fork branch. --force is needed because the branch name
  # is deterministic (autosolve/issue-N) and a previous failed run may have
  # already pushed to it.
  git push --set-upstream fork "$branch_name" --force

  # Build PR body: prefer Claude-written .autosolve-pr-body, then custom
  # template, then fall back to a summary of all commits on the branch.
  local pr_body
  if [ -n "$pr_body_template" ]; then
    pr_body="$pr_body_template"
    # Support template variables
    local summary=""
    if [ -f "$AUTOSOLVE_TMPDIR/implementation_result.txt" ]; then
      summary="$(truncate_output 200 "$(sed '/^IMPLEMENTATION_RESULT/d' "$AUTOSOLVE_TMPDIR/implementation_result.txt")")"
    fi
    pr_body="${pr_body//\{\{SUMMARY\}\}/$summary}"
    pr_body="${pr_body//\{\{BRANCH\}\}/$branch_name}"
  elif [ -f "$AUTOSOLVE_TMPDIR/autosolve-pr-body" ]; then
    pr_body="$(cat "$AUTOSOLVE_TMPDIR/autosolve-pr-body")"
  else
    # Summarize all commits on the branch relative to the base
    pr_body="$(git log "${pr_base_branch}..HEAD" --format='%B' | head -200)"
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

  # Ensure all PR labels exist on the repo (gh pr create fails if they don't).
  # Label creation is best-effort — it fails harmlessly if the label already exists.
  local label
  while IFS= read -r label; do
    label="$(echo "$label" | xargs)"
    [ -z "$label" ] && continue
    GH_TOKEN="${pr_create_token}" gh label create "$label" \
      --repo "${GITHUB_REPOSITORY:-}" \
      --color "6f42c1" || true
  done <<< "${pr_labels//,/$'\n'}"

  local pr_url
  pr_url="$(GH_TOKEN="${pr_create_token}" gh pr create \
    --repo "${GITHUB_REPOSITORY:-}" \
    --head "${fork_owner}:${branch_name}" \
    --base "${pr_base_branch}" \
    $draft_flag \
    --title "$pr_title" \
    --body "$pr_body" \
    --label "$pr_labels")" || {
    log_error "Failed to create PR: $pr_url"
    return 1
  }

  log_notice "PR created: $pr_url"
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
  summary="$(truncate_output 200 "$(echo "$result_text" | sed '/^IMPLEMENTATION_RESULT/d')")"

  set_output "status" "$status"
  set_output "pr_url" "$pr_url"
  set_output "branch_name" "$branch_name"
  set_output_multiline "summary" "$summary"
  set_output_multiline "result" "$result_text"

  write_step_summary <<EOF
## Autosolve Implementation
**Status:** $status
$([ -n "$pr_url" ] && echo "**PR:** $pr_url")
$([ -n "$branch_name" ] && echo "**Branch:** \`$branch_name\`")
$([ -n "$summary" ] && printf '### Summary\n%s' "$summary")
EOF
}

cleanup_implement() {
  # credential.helper may not exist if the push step was skipped (e.g.,
  # assessment returned SKIP or security check failed).
  git config --local --unset credential.helper || true
  # fork remote may not exist if push_and_pr was never reached.
  git remote remove fork || true
  rm -rf "${AUTOSOLVE_TMPDIR:-}"
}
