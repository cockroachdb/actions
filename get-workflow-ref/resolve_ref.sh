#!/usr/bin/env bash
# Resolve the ref a caller used to invoke a reusable workflow.
#
# Required env vars:
#   WORKFLOW_REF    — github.workflow_ref (e.g. owner/repo/.github/workflows/caller.yml@refs/heads/main)
#   REPO            — github.repository  (e.g. owner/repo)
#   REF             — github.ref         (e.g. refs/heads/main)
#   WORKFLOW_NAME   — substring to match in the caller's uses line
#
# Outputs (appended to $GITHUB_OUTPUT):
#   ref             — the resolved ref string
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
# shellcheck source=../actions_helpers.sh
source "$SCRIPT_DIR/../actions_helpers.sh"

workflow_ref="${WORKFLOW_REF}"

# Strip "owner/repo/" prefix and "@refs/..." suffix to get the
# caller's workflow file path.
workflow_path="${workflow_ref#"${REPO}/"}"
workflow_path="${workflow_path%@*}"

if [ ! -f "$workflow_path" ]; then
  log_error "Could not find caller workflow at: $workflow_path"
  exit 1
fi

# Find the uses: line that references our workflow and extract the ref.
# Filter to uses: lines first (avoids matching comments or job names),
# then match the workflow name as a literal string.
if ! match="$(grep 'uses:' "$workflow_path" | grep --fixed-strings -- "$WORKFLOW_NAME" | head -1)"; then
  log_error "Could not find '$WORKFLOW_NAME' in $workflow_path"
  exit 1
fi

# Handle local reference (./): use the caller's own ref.
if [[ "$match" == *"./.github/workflows"* ]]; then
  ref="${REF}"
else
  ref="$(printf '%s\n' "$match" | sed 's/.*@//' | awk '{print $1}')"
fi

if [ -z "$ref" ]; then
  log_error "Could not parse ref from: $match"
  exit 1
fi

set_output "ref" "$ref"
log_notice "Resolved workflow ref: $ref"
