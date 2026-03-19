#!/usr/bin/env bash
# Entry point for autosolve action steps.
#
# Composite action steps run in a fresh shell, so sourcing scripts directly
# would leave them cd'd to the scripts/ directory instead of the workspace.
# This wrapper solves three problems:
#   1. Sources the target script (which cd's to its own directory for clean
#      relative imports of shared.sh, actions_helpers.sh, etc.).
#   2. Restores the original working directory so the function runs in the
#      caller's workspace (where the repo checkout lives).
#   3. Manages a shared AUTOSOLVE_TMPDIR across composite action steps
#      (each step is a new shell process).
#
# Usage: run_step.sh <script> <function> [args...]
#
# Examples:
#   run_step.sh shared   validate_inputs
#   run_step.sh assess   run_assessment
#   run_step.sh implement security_check
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"

# Create a per-run temp directory if one doesn't already exist.
if [ -z "${AUTOSOLVE_TMPDIR:-}" ]; then
  AUTOSOLVE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/autosolve_XXXXXX")"
  export AUTOSOLVE_TMPDIR
  # Persist across composite action steps (each step is a new shell process).
  echo "AUTOSOLVE_TMPDIR=$AUTOSOLVE_TMPDIR" >> "${GITHUB_ENV:-/dev/null}"
fi

script="$1"
func="$2"
shift 2

# Sourced scripts cd to their own directory for clean relative imports.
# Save and restore cwd so the function runs in the workspace.
ORIG_DIR="$(pwd)"
source "$STEP_DIR/scripts/${script}.sh"
cd "$ORIG_DIR"

"$func" "$@"
