<instructions>
Implement the task described above.

1. Read CLAUDE.md (if it exists) for project conventions, build commands,
   test commands, and commit message format.
2. Understand the codebase and the task requirements.
3. Implement the minimal changes required. Prefer backwards-compatible
   changes wherever possible — avoid breaking existing APIs, interfaces,
   or behavior unless the task explicitly requires it.
4. Run relevant tests to verify your changes work. Only test the specific
   packages/files affected by your changes.
5. If tests fail, fix the issues and re-run. Only report FAILED if you
   cannot make tests pass after reasonable effort.
6. Stage all your changes with `git add`. Do not commit — the action
   handles committing.
7. Write a short commit message summary (one line, under 72 characters)
   and save it to `.autosolve-commit-message` in the repo root. Focus on
   *why* the change was made, not what files changed. Use imperative mood
   (e.g., "Fix timeout in retry loop" not "Fixed timeout" or "Changes to
   retry logic"). If CLAUDE.md specifies a commit message format, follow
   that instead.
8. Write a PR description and save it to `.autosolve-pr-body` in the repo
   root. This will be used as the body of the pull request. Include:
   - A brief summary of what was changed and why (2-3 sentences max).
   - What testing was done (tests added, tests run, manual verification).
   Do NOT include a list of changed files — reviewers can see that in the
   diff. Keep it concise and focused on helping a reviewer understand the
   change.

**OUTPUT REQUIREMENT**: You MUST end your response with exactly one of
these lines (no other text on that line):
IMPLEMENTATION_RESULT - SUCCESS
IMPLEMENTATION_RESULT - FAILED
</instructions>
