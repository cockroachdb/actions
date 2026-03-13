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

The test runner discovers all `*_test.sh` files under action subdirectories via
the glob `*/**_test.sh`. Each action's tests are self-contained shell scripts
that set up temporary git repos and validate behavior.

## Adding a New Action

1. Create a subdirectory named after the action (e.g., `my-action/`)
2. Add `action.yml` (composite action) and implementation scripts
3. Add `*_test.sh` in the same directory — the top-level `test.sh` will pick it up automatically
4. Document the action in `README.md` under the Actions section

## Conventions

- Tests are written in plain bash using a `run_test` helper pattern
  (function name, expected exit code, expected output substring, command).  As
  the repo grows, we can revisit this convention if a different testing approach
  makes more sense.
- Prefer to avoid action or workload steps that are code encoded in strings.
  Instead create a separate file with the proper extension. This helps for
  syntax highlighting and testability.
- update CHANGELOG.md with each change.  If it's a breaking change, prefix
  with "Breaking Change: ". Try to keep change descriptions focused on user
  outcome.
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
- Autosolve scripts (`assess.sh`, `implement.sh`, `jira.sh`, `shared.sh`) source their
  own dependencies via `BASH_SOURCE`-relative paths. No caller needs to source the
  chain — just source the script you need. Re-sourcing is idempotent.
