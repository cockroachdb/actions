# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

Breaking changes are prefixed with "Breaking Change: ".

## [Unreleased]

### Added

- `autosolve/assess` action: evaluate tasks for automated resolution suitability
  using Claude in read-only mode.
- `autosolve/implement` action: autonomously implement solutions, validate
  security, push to fork, and create PRs using Claude.
- `github-issue-autosolve` reusable workflow: turnkey GitHub Issues
  integration with issue comments and label management.
- `jira-autosolve` reusable workflow: turnkey Jira integration composing
  autosolve/assess + autosolve/implement with ticket comments and transitions.
- `autotag-from-changelog` action: tag and push from CHANGELOG.md version
  change.
