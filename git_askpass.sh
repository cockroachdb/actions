#!/usr/bin/env bash
# GIT_ASKPASS helper. Reads credentials from the GIT_USER and GIT_PASSWORD
# environment variables and prints them when git prompts for credentials.
#
# Usage:
#   export GIT_ASKPASS=/path/to/git_askpass.sh
#   export GIT_TERMINAL_PROMPT=0   # fail fast if creds are missing
#   GIT_USER=x-access-token GIT_PASSWORD="$TOKEN" git fetch ...
#
# Git invokes this script with the prompt as $1 — e.g.
#   "Username for 'https://github.com':"
#   "Password for 'https://x-access-token@github.com':"
set -euo pipefail

case "$1" in
  Username*) echo "${GIT_USER:?GIT_USER not set}" ;;
  Password*) echo "${GIT_PASSWORD:?GIT_PASSWORD not set}" ;;
  *) echo "git_askpass.sh: unexpected prompt: $1" >&2; exit 1 ;;
esac
