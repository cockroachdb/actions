# CLAUDE.md

## Overview

This is a monorepo of reusable GitHub Actions and workflows for CockroachDB
projects. Each action lives in its own subdirectory (e.g.,
`autotag-from-changelog/`) with an `action.yml` and supporting scripts.

## Running Tests

Run all tests:
```sh
./test.sh
```

The test runner discovers all `*_test.sh` files in the repository using `find`
(with `-mindepth 1`). Each test file is a self-contained shell script that
sources `test_helpers.sh` and validates behavior.

## Adding a New Action

1. Create a subdirectory named after the action (e.g., `my-action/`)
2. Add `action.yml` (composite action) and implementation scripts
3. Add `*_test.sh` in the same directory — the top-level `test.sh` will pick it up automatically
4. Document the action in `README.md` under the Actions section

## Conventions

- Tests are written in plain bash using helpers from `test_helpers.sh`:
  `expect_success`, `expect_failure`, `expect_success_output`,
  `expect_failure_output`, `check_contains`, and `check_contains_pattern`.
- Prefer to avoid action or workload steps that are code encoded in strings.
  Instead create a separate file with the proper extension. This helps for
  syntax highlighting and testability.
- update CHANGELOG.md with each change.  If it's a breaking change, prefix
  with "Breaking Change: ". Try to keep change descriptions focused on user
  outcome. New entries go above older ones (the changelog grows upward).
- CI runs on PRs: `test.yml` runs `./test.sh`, `actionlint.yml` lints workflow YAML files
- Every shellcheck suppression (`disable`, `source`, etc.) must include a short
  comment explaining why the suppression is needed. SC1091 (can't follow
  sourced file) is disabled globally in `.shellcheckrc` since all sources use
  dynamic `$SCRIPT_DIR` paths.
- In test files, prefer `cd "$(dirname "${BASH_SOURCE[0]}")"` at the top and then use literal
  relative paths for `source` (e.g., `source ../../actions_helpers.sh`). This
  enables IDE go-to-definition via `source-path=SCRIPTDIR` in `.shellcheckrc`
  without needing `# shellcheck source=` directives. In production scripts that
  cannot `cd`, use `SCRIPT_DIR` with `# shellcheck source=` directives for
  navigation.
- `actions_helpers.sh` at the repo root provides shared helpers (`log_error`, `log_warning`,
  `log_notice`, `set_output`, `set_output_multiline`). Scripts source it via
  a relative path after `cd`-ing to their own directory.
- In shell scripts, prefer long options over short flags for readability
  (e.g., `grep --quiet --fixed-strings` instead of `grep -qF`,
  `curl --silent --output /dev/null` instead of `curl -s -o /dev/null`).
  Exceptions: flags with no long form (e.g., `git checkout -b`) and
  universally understood short forms in test helpers (e.g., `rm -rf`).
- Never discard stderr (e.g., `2>/dev/null`) in shell scripts or action
  steps. Suppressing stderr hides real errors and makes debugging harder.
  Using `2>&1` to merge stderr into stdout is acceptable in test helpers
  that need to capture all output for assertion, but avoid it in
  production scripts. Run each command on its own line so that `bash -e`
  (the default for GitHub Actions `run` steps) halts on failure and the
  return code is checked automatically.
- Use snake_case for multi-word action output names (e.g., `tag_created`
  instead of `tag-created`). Hyphens in output names are parsed as subtraction
  in GitHub Actions expressions.
- In workflow YAML files, always look up and use the latest major version of
  built-in GitHub Actions (e.g., `actions/checkout`, `actions/upload-artifact`).
  Do not rely on memorized version numbers — they go stale.
- Do not silently swallow errors. In shell scripts, avoid `|| return 0`,
  `|| true`, or `|| :` to suppress failures without logging — use
  `log_warning` to surface what went wrong. In Go code, avoid `return nil`
  on error paths without logging or returning the error. If ignoring an
  error is genuinely correct (e.g., best-effort cleanup), add a comment
  explaining why it's safe to ignore.

## Commit messages
- If a commit updates or adds a specific action, prefix the commit with that
  action. 
