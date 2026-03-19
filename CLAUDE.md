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

The test runner discovers all `*_test.sh` files under action subdirectories
using `find` (with `-mindepth 2`). Each action's tests are self-contained shell
scripts that set up temporary git repos and validate behavior.

## Adding a New Action

1. Create a subdirectory named after the action (e.g., `my-action/`)
2. Add `action.yml` (composite action) and implementation scripts
3. Add `*_test.sh` in the same directory — the top-level `test.sh` will pick it up automatically
4. Document the action in `README.md` under the Actions section

## Conventions

- Tests are written in plain bash using a `run_test` helper pattern
  (function name, expected exit code, expected output substring, command).
  As the repo grows, we can revisit this convention if a different testing
  approach makes more sense.
- Prefer to avoid action or workload steps that are code encoded in strings.
  Instead create a separate file with the proper extension. This helps for
  syntax highlighting and testability.
- update CHANGELOG.md with each change.  If it's a breaking change, prefix
  with "Breaking Change: ". Try to keep change descriptions focused on user
  outcome.
- CI runs on PRs: `test.yml` runs `./test.sh`, `actionlint.yml` lints workflow YAML files
