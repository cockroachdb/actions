# cockroachdb/actions

Reusable GitHub Actions and workflows for CockroachDB projects.

## Actions

### autotag-from-changelog

Creates git tags from CHANGELOG.md versions. Fails only when there is content
under `[Unreleased]` and the previous release version tag does not yet exist;
otherwise it succeeds even if `[Unreleased]` contains entries.

**Usage:**

```yaml
- uses: cockroachdb/actions/autotag-from-changelog@v0
```

**Inputs:**

| Name             | Default        | Description                |
| ---------------- | -------------- | -------------------------- |
| `changelog-path` | `CHANGELOG.md` | Path to the changelog file |

**Required permissions:**

```yaml
permissions:
  contents: write
```

### changelog-check

Validates that CHANGELOG.md follows the [Keep a Changelog](https://keepachangelog.com/)
standard. Ensures proper changelog structure, version ordering,
and detects breaking changes to enable automated version bump determination.

**Usage:**

```yaml
- uses: cockroachdb/actions/changelog-check@v0
  with:
    check-mode: diff
    base-ref: ${{ github.event.pull_request.base.ref }}
```

**Inputs:**

| Name               | Default        | Description                                                              |
| ------------------ | -------------- | ------------------------------------------------------------------------ |
| `changelog-path`   | `CHANGELOG.md` | Path to the changelog file                                               |
| `validation-depth` | `1`            | How many changelog entries to validate starting from the most recent     |
| `check-mode`       | `unreleased`   | Check mode for breaking change detection: `unreleased` (entire Unreleased section) or `diff` (PR changes only). Does not affect format/version validation, which always runs. |
| `base-ref`         | `''`           | Required when `check-mode` is `diff`. The base git ref to compare against for detecting breaking changes in the diff only (e.g., `main`, or `github.event.pull_request.base.ref` in PRs). Not needed for `unreleased` mode. |

**Outputs:**

| Name            | Description                                                      |
| --------------- | ---------------------------------------------------------------- |
| `is_valid`      | Whether the CHANGELOG format and version ordering are valid      |
| `has_breaking`  | Whether breaking changes were detected                           |

**Features:**

- Validates CHANGELOG.md format using Keep a Changelog standard
- Checks that versions are in descending order (newest first)
- Checks that release dates are in descending order
- Detects breaking changes via two methods:
  - Entries prefixed with `Breaking Change:` in any section
  - Presence of a `### Removed` section header
- Supports checking entire Unreleased section or only PR diff

### release-version-extract

Extracts the current version from CHANGELOG.md and determines the next version
based on unreleased changes. Analyzes changelog entries to automatically
determine whether a major, minor, or patch version bump is needed.

**Usage:**

```yaml
- uses: cockroachdb/actions/release-version-extract@v0
  id: version
- run: echo "Next version will be ${{ steps.version.outputs.next_version }}"
```

**Inputs:**

| Name             | Default        | Description                |
| ---------------- | -------------- | -------------------------- |
| `changelog-path` | `CHANGELOG.md` | Path to the changelog file |

**Outputs:**

| Name                 | Description                                                      |
| -------------------- | ---------------------------------------------------------------- |
| `current_version`    | Current latest released version (empty if no releases)           |
| `next_version`       | Suggested next version based on unreleased changes               |
| `bump_type`          | Type of version bump (`major`/`minor`/`patch`/`initial`, or empty if no changes) |
| `has_unreleased`     | Whether there are unreleased changes (`true`/`false`)            |
| `unreleased_changes` | Text content of unreleased changelog entries                     |

**Features:**

- Automatically determines version bump type from changelog entries
- Detects major bumps when breaking changes are present (lines prefixed with `Breaking Change:` or `### Removed` section)
- Handles initial releases (first release → 0.1.0)
- Returns empty `bump_type` when there are no unreleased changes
- Follows semantic versioning principles

### get-workflow-ref

Resolves the git ref that a caller used to invoke a reusable workflow by parsing
the caller's workflow file. Useful for reusable workflows that need to reference
other resources (actions, scripts, etc.) at the same version they were invoked with.

**Usage:**

```yaml
jobs:
  my-job:
    runs-on: ubuntu-latest
    steps:
      - uses: cockroachdb/actions/get-workflow-ref@v0
        id: ref
      - run: echo "Workflow was called with ref ${{ steps.ref.outputs.ref }}"
```

**Outputs:**

| Name  | Description                                                      |
| ----- | ---------------------------------------------------------------- |
| `ref` | Git ref used to invoke this workflow (e.g., `v1`, `main`, commit SHA) |

**Features:**

- No API calls or extra permissions needed
- Works by parsing the caller's workflow file from the event payload
- Returns the exact ref specified in the workflow call (tag, branch, or SHA)

## Workflows

### create-release-pr

Reusable workflow that automates version bump pull requests. Checks for unreleased
changes in CHANGELOG.md, determines the next semantic version, updates the changelog
with the release date, optionally runs custom update scripts, and creates a PR from
a fork to the upstream repository.

**Usage:**

```yaml
name: Create Version Bump PR

on:
  workflow_dispatch:

jobs:
  create-release-pr:
    uses: cockroachdb/actions/.github/workflows/create-release-pr.yml@v0
    with:
      fork_owner: my-release-bot
      fork_repo: my-repo-fork
      pr_base_branch: main
      release_date: 2026-03-30
      git_user_name: my-release-bot
      git_user_email: my-release-bot@users.noreply.github.com
      build_script: .github/scripts/build_script.sh
      files_to_commit: |
        package.json
        package-lock.json
    secrets:
      fork_push_token: ${{ secrets.FORK_PAT }}
      pr_create_token: ${{ secrets.PR_PAT }}
```

**Inputs:**

| Name                        | Required | Default | Description                                      |
| --------------------------- | -------- | ------- | ------------------------------------------------ |
| `fork_owner`                | Yes      |         | GitHub username or org that owns the fork        |
| `fork_repo`                 | Yes      |         | Repository name of the fork                      |
| `pr_base_branch`            | No       | `""`    | Base branch for the PR (defaults to repository default branch) |
| `build_script`              | No       | `""`    | Optional path to a bash script to execute before committing. The `VERSION` environment variable will be available. |
| `files_to_commit`           | No       | `""`    | Newline-separated list of file paths to commit (in addition to CHANGELOG.md which is always included). Paths should be relative to repository root. |
| `release_date`              | No       | `""`    | Release date in YYYY-MM-DD format (defaults to current date) |
| `git_user_name`             | No       | `github-actions[bot]` | Git user name for commits |
| `git_user_email`            | No       | `github-actions[bot]@users.noreply.github.com` | Git user email for commits |

**Secrets:**

| Name               | Required | Description                                      |
| ------------------ | -------- | ------------------------------------------------ |
| `fork_push_token`  | Yes      | PAT with push access to the fork                 |
| `pr_create_token`  | Yes      | PAT with permission to create PRs on the upstream repo |

**Outputs:**

| Name     | Description                                                      |
| -------- | ---------------------------------------------------------------- |
| `pr_url` | URL of the created pull request (empty if no unreleased changes) |

**Features:**

- Automatically detects unreleased changes in CHANGELOG.md
- Determines next version using semver principles
- Updates CHANGELOG.md with new version and customizable release date (defaults to current date)
- Supports custom bash scripts to run before committing (via `build_script` file path)
- Creates PR from fork to upstream repository
- Exits gracefully when no unreleased changes exist

### github-issue-autosolve

Reusable workflow that automatically solves GitHub issues using Claude. When
triggered (typically by adding a label), it assesses whether the issue is
suitable for automation, implements a fix, pushes to a fork, and opens a draft
PR. Comments are posted on the issue at each stage.

**Usage:**

Create a caller workflow in your repo (e.g. `.github/workflows/autosolve.yml`):

```yaml
name: Autosolve
on:
  issues:
    types: [labeled]

jobs:
  autosolve:
    if: github.event.label.name == 'autosolve'
    uses: cockroachdb/actions/.github/workflows/github-issue-autosolve.yml@main
    with:
      issue_number: ${{ github.event.issue.number }}
      issue_title: ${{ github.event.issue.title }}
      issue_body: ${{ github.event.issue.body }}
      vertex_project_id: my-gcp-project
      vertex_workload_identity_provider: projects/123/locations/global/workloadIdentityPools/pool/providers/provider
      vertex_service_account: autosolve@my-gcp-project.iam.gserviceaccount.com
      fork_owner: my-bot-user
      fork_repo: my-repo
    secrets:
      fork_push_token: ${{ secrets.FORK_PUSH_TOKEN }}
      pr_create_token: ${{ secrets.PR_CREATE_TOKEN }}
```

**Inputs:**

| Name | Required | Default | Description |
| ---- | -------- | ------- | ----------- |
| `issue_number` | yes | | GitHub issue number |
| `issue_title` | yes | | Issue title |
| `issue_body` | yes | | Issue body text |
| `vertex_project_id` | yes | | GCP project ID for Vertex AI |
| `vertex_workload_identity_provider` | yes | | Workload identity provider resource name |
| `vertex_service_account` | yes | | Service account for Vertex AI |
| `fork_owner` | yes | | GitHub user/org that owns the fork |
| `fork_repo` | yes | | Repository name of the fork |
| `trigger_label` | no | `autosolve` | Label that triggers the workflow |
| `allowed_tools` | no | *(action default)* | Claude `--allowedTools` string |
| `claude_cli_version` | no | `2.1.79` | Claude CLI version to install |
| `model` | no | `claude-opus-4-6` | Claude model ID |
| `max_retries` | no | `3` | Maximum implementation attempts |
| `vertex_region` | no | `us-east5` | GCP region for Vertex AI |
| `git_user_name` | no | `autosolve[bot]` | Git author/committer name |
| `git_user_email` | no | `autosolve[bot]@users.noreply.github.com` | Git author/committer email |
| `verbose_logging` | no | `false` | Enable verbose Claude logging in step output |
| `timeout_minutes` | no | `20` | Job timeout in minutes |

**Secrets:**

| Name | Required | Description |
| ---- | -------- | ----------- |
| `fork_push_token` | yes | PAT with push access to the fork repository |
| `pr_create_token` | yes | PAT with permission to create PRs on the upstream repo |

The workflow also uses the automatically minted `GITHUB_TOKEN` for issue
comments, label management, and PR lookups.

**Outputs:**

| Name | Description |
| ---- | ----------- |
| `status` | `SUCCESS`, `FAILED`, `SKIPPED`, or `EXISTING_PR` |
| `pr_url` | URL of the created (or existing) PR |

**Required caller permissions:**

```yaml
permissions:
  contents: read
  issues: write
  pull-requests: read
  id-token: write   # for Vertex AI workload identity federation
```

**How it works:**

1. Checks if a PR already exists for this issue (via head branch name).
2. Authenticates to Google Cloud via workload identity federation.
3. **Assess** — Claude evaluates the issue in read-only mode and decides
   `PROCEED` or `SKIP`.
4. **Implement** — Claude implements a fix, pushes to the fork, and opens a
   draft PR on the upstream repo.
5. Comments on the issue with the outcome and removes the trigger label.

## Development

Run all tests locally:

```sh
./test.sh
```

Tests also run automatically on pull requests via CI.
