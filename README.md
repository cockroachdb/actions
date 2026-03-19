# cockroachdb/actions

Reusable GitHub Actions and workflows for CockroachDB projects.

## Actions

### autotag-from-changelog

Creates git tags from CHANGELOG.md versions. Fails only when there is content
under `[Unreleased]` and the previous release version tag does not yet exist;
otherwise it succeeds even if `[Unreleased]` contains entries.

**Usage:**

```yaml
- uses: cockroachdb/actions/autotag-from-changelog@v1
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

### autosolve

Uses Claude Code to autonomously assess and implement solutions for tasks.
Organized as two composite actions that can be used independently or together,
plus reusable workflows for common integrations.

#### Actions

**`autosolve/assess`** — Runs Claude in read-only mode to evaluate whether a
task is suitable for automated resolution.

```yaml
- uses: cockroachdb/actions/autosolve/assess@v1
  id: assess
  with:
    prompt: "Fix the login bug described in issue #42"
```

| Input | Default | Description |
|---|---|---|
| `prompt` | | Task description for Claude to assess |
| `skill` | | Path to a skill/prompt file relative to the repo root |
| `additional_instructions` | | Extra context appended after the task prompt |
| `assessment_criteria` | *(built-in)* | Custom criteria for PROCEED/SKIP decision |
| `model` | `claude-opus-4-6` | Claude model ID |
| `blocked_paths` | `.github/workflows/` | Comma-separated path prefixes that cannot be modified |

| Output | Description |
|---|---|
| `assessment` | `PROCEED` or `SKIP` |
| `summary` | Human-readable assessment reasoning |
| `result` | Full Claude result text |

**`autosolve/implement`** — Runs Claude to implement a solution, validates
changes against blocked paths, pushes to a fork, and creates a single-commit
PR.

```yaml
- uses: cockroachdb/actions/autosolve/implement@v1
  if: steps.assess.outputs.assessment == 'PROCEED'
  with:
    prompt: "Fix the login bug described in issue #42"
    fork_owner: my-bot
    fork_repo: my-repo
    fork_push_token: ${{ secrets.FORK_PUSH_TOKEN }}
    pr_create_token: ${{ secrets.PR_CREATE_TOKEN }}
```

| Input | Default | Description |
|---|---|---|
| `prompt` | | Task description for Claude to implement |
| `skill` | | Path to a skill/prompt file relative to the repo root |
| `additional_instructions` | | Extra instructions appended after the task prompt |
| `allowed_tools` | *(read/write/git tools)* | Claude `--allowedTools` string |
| `model` | `claude-opus-4-6` | Claude model ID |
| `max_retries` | `3` | Maximum implementation attempts |
| `create_pr` | `true` | Whether to create a PR from the changes |
| `pr_base_branch` | *(repo default)* | Base branch for the PR |
| `pr_labels` | `autosolve` | Comma-separated labels to apply |
| `pr_draft` | `true` | Whether to create as a draft PR |
| `pr_title` | *(from commit)* | PR title |
| `pr_body_template` | *(built-in)* | Template with `{{SUMMARY}}`, `{{BRANCH}}` placeholders |
| `fork_owner` | | GitHub user/org that owns the fork |
| `fork_repo` | | Fork repository name |
| `fork_push_token` | | PAT with push access to the fork |
| `pr_create_token` | | PAT with PR create access on upstream |
| `blocked_paths` | `.github/workflows/` | Comma-separated blocked path prefixes |
| `git_user_name` | `autosolve[bot]` | Git author/committer name |
| `git_user_email` | `autosolve[bot]@users.noreply.github.com` | Git author/committer email |
| `branch_suffix` | *(timestamp)* | Suffix for branch name (`autosolve/<suffix>`) |

| Output | Description |
|---|---|
| `status` | `SUCCESS` or `FAILED` |
| `pr_url` | URL of the created PR |
| `summary` | Human-readable summary |
| `result` | Full Claude result text |
| `branch_name` | Branch pushed to the fork |

#### Reusable Workflows

**GitHub Issue Autosolve** — Composes assess + implement with GitHub issue
comments and label management. Triggered via `workflow_call`.

```yaml
jobs:
  solve:
    uses: cockroachdb/actions/.github/workflows/github-issue-autosolve.yml@v1
    with:
      issue_number: ${{ github.event.issue.number }}
      issue_title: ${{ github.event.issue.title }}
      issue_body: ${{ github.event.issue.body }}
      fork_owner: my-bot
      fork_repo: my-repo
    secrets:
      fork_push_token: ${{ secrets.FORK_PUSH_TOKEN }}
      pr_create_token: ${{ secrets.PR_CREATE_TOKEN }}
```

#### Authentication

**Reusable workflows** accept `auth_mode` as an input (`vertex` or omit for API
key) and handle env var setup internally.

**Direct composite action usage** requires the caller to set up auth and pass
the env vars on each action step:

```yaml
# Example: Vertex AI auth for direct action usage
- uses: google-github-actions/auth@v3
  with:
    project_id: my-project
    service_account: my-sa@my-project.iam.gserviceaccount.com
    workload_identity_provider: projects/.../providers/...

- uses: cockroachdb/actions/autosolve/assess@v1
  env:
    CLAUDE_CODE_USE_VERTEX: "1"
    ANTHROPIC_VERTEX_PROJECT_ID: my-project
    CLOUD_ML_REGION: us-east5
  with:
    prompt: "Fix the bug"
```

Alternatively, set `ANTHROPIC_API_KEY` in the environment for direct API
access.

## Development

Run all tests locally:

```sh
./test.sh
```

Tests also run automatically on pull requests via CI.
