#!/usr/bin/env bash

# Configure git (and optionally GOPRIVATE) so `go`/gazelle can fetch the private
# repos using the per-org installation tokens minted by the action. Each rewrite
# is scoped to the exact private repo it authenticates, so unrelated public
# siblings are cloned without a token attached.
#
# Note: deliberately no `set -x`. The tokens must not be echoed to the log.
#
# GitHub-hosted runners are ephemeral, so the global git config written here does
# not need cleanup. On self-hosted runners with a persistent HOME, the caller is
# responsible for removing these url.*.insteadOf entries after the job.

set -euo pipefail

goprivate_entries=""

# configure_org <owner> <token> <comma-separated-repos>
configure_org() {
  local owner="$1" token="$2" repos="$3"
  [[ -z "${repos}" ]] && return 0
  : "${token:?no token minted for ${owner} (is the App installed and scoped there?)}"

  local repo
  IFS=',' read -ra repo_arr <<< "${repos}"
  for repo in "${repo_arr[@]}"; do
    git config --global \
      "url.https://x-access-token:${token}@github.com/${owner}/${repo}.insteadOf" \
      "https://github.com/${owner}/${repo}"
    goprivate_entries="${goprivate_entries:+${goprivate_entries},}github.com/${owner}/${repo}"
  done
}

configure_org "cockroachlabs" "${COCKROACHLABS_TOKEN:-}" "${COCKROACHLABS_REPOSITORIES:-}"
configure_org "cockroachdb" "${COCKROACHDB_TOKEN:-}" "${COCKROACHDB_REPOSITORIES:-}"

if [[ "${CONFIGURE_GOPRIVATE:-true}" == "true" && -n "${goprivate_entries}" ]]; then
  # Merge with any GOPRIVATE already present in the environment.
  if [[ -n "${GOPRIVATE:-}" ]]; then
    merged="${GOPRIVATE},${goprivate_entries}"
  else
    merged="${goprivate_entries}"
  fi
  echo "GOPRIVATE=${merged}" >> "${GITHUB_ENV}"
fi
