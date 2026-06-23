#!/usr/bin/env bash

# Group the `owner/repo` list by org and emit one comma-separated repo list per
# supported org as step outputs (e.g. `cockroachlabs=a,b`). A GitHub App
# installation token is scoped to a single org's installation and a composite
# action cannot loop `uses:` steps, so the action mints one token per supported
# org; any other org is rejected here with a clear error.

set -euo pipefail

: "${REPOSITORIES:?must be set by the action}"

# Orgs the go-deps App is installed on. Keep in sync with the per-org token
# steps in action.yml (one create-github-app-token step each).
supported=(cockroachlabs cockroachdb)

declare -A repos_by_org=()
for org in "${supported[@]}"; do
  repos_by_org["${org}"]=""
done

# Accept comma- and/or newline-separated entries.
entries="${REPOSITORIES//,/$'\n'}"
while IFS= read -r entry; do
  # Trim surrounding whitespace.
  entry="${entry#"${entry%%[![:space:]]*}"}"
  entry="${entry%"${entry##*[![:space:]]}"}"
  [[ -z "${entry}" ]] && continue

  owner="${entry%%/*}"
  repo="${entry#*/}"
  if [[ "${entry}" != */* || -z "${owner}" || -z "${repo}" || "${repo}" == */* ]]; then
    echo "::error::Invalid repository '${entry}'; expected 'owner/repo'." >&2
    exit 1
  fi
  if [[ -z "${repos_by_org[${owner}]+x}" ]]; then
    echo "::error::Unsupported org '${owner}'. Supported orgs: ${supported[*]}." >&2
    exit 1
  fi

  repos_by_org["${owner}"]="${repos_by_org[${owner}]:+${repos_by_org[${owner}]},}${repo}"
done <<< "${entries}"

{
  for org in "${supported[@]}"; do
    echo "${org}=${repos_by_org[${org}]}"
  done
} >> "${GITHUB_OUTPUT}"
