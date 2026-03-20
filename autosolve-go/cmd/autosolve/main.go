package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"strconv"
	"strings"

	"github.com/cockroachdb/actions/autosolve-go/internal/action"
	"github.com/cockroachdb/actions/autosolve-go/internal/assess"
	"github.com/cockroachdb/actions/autosolve-go/internal/claude"
	"github.com/cockroachdb/actions/autosolve-go/internal/config"
	"github.com/cockroachdb/actions/autosolve-go/internal/git"
	"github.com/cockroachdb/actions/autosolve-go/internal/github"
	"github.com/cockroachdb/actions/autosolve-go/internal/implement"
	"github.com/cockroachdb/actions/autosolve-go/internal/prompt"
	"github.com/cockroachdb/actions/autosolve-go/internal/security"
)

const usage = `Usage: autosolve <command>

Commands:
  assess          Run assessment phase
  implement       Run implementation phase
  security        Run security check on working tree
  prompt build    Assemble the full prompt file
  prompt issue    Build prompt from GitHub issue context
  comment         Post a comment on a GitHub issue
  label remove    Remove a label from a GitHub issue`

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	if len(os.Args) < 2 {
		fatalf(usage)
	}

	// Join args to support two-word commands like "prompt build"
	cmd := os.Args[1]
	if len(os.Args) > 2 {
		cmd = os.Args[1] + " " + os.Args[2]
	}

	var err error
	switch cmd {
	case "assess":
		err = runAssess(ctx)
	case "implement":
		err = runImplement(ctx)
	case "security":
		err = runSecurity()
	case "prompt build":
		err = runPromptBuild()
	case "prompt issue":
		err = runPromptIssue()
	case "comment":
		err = runComment(ctx)
	case "label remove":
		err = runLabelRemove(ctx)
	default:
		fatalf("unknown command: %s\n\n%s", os.Args[1], usage)
	}

	if err != nil {
		action.LogError(err.Error())
		os.Exit(1)
	}
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}

func runAssess(ctx context.Context) error {
	cfg, err := config.LoadAssessConfig()
	if err != nil {
		return err
	}
	if err := config.ValidateAuth(); err != nil {
		return err
	}
	tmpDir, err := ensureTmpDir()
	if err != nil {
		return err
	}
	return assess.Run(ctx, cfg, &claude.CLIRunner{}, tmpDir)
}

func runImplement(ctx context.Context) error {
	cfg, err := config.LoadImplementConfig()
	if err != nil {
		return err
	}
	if err := config.ValidateAuth(); err != nil {
		return err
	}
	tmpDir, err := ensureTmpDir()
	if err != nil {
		return err
	}

	gitClient := &git.CLIClient{}
	defer implement.Cleanup(gitClient)

	ghClient := &github.GithubClient{Token: cfg.PRCreateToken}
	return implement.Run(ctx, cfg, &claude.CLIRunner{}, ghClient, gitClient, tmpDir)
}

func runSecurity() error {
	cfg, err := config.LoadSecurityConfig()
	if err != nil {
		return err
	}
	gitClient := &git.CLIClient{}
	violations, err := security.Check(gitClient, cfg.BlockedPaths)
	if err != nil {
		return err
	}
	if len(violations) > 0 {
		for _, v := range violations {
			action.LogError(v)
		}
		return fmt.Errorf("security check failed: %d violation(s) found", len(violations))
	}
	action.LogNotice("Security check passed")
	return nil
}

func runPromptBuild() error {
	footerType := envOrDefault("INPUT_FOOTER_TYPE", "implementation")
	cfg := &config.Config{
		Prompt:                 os.Getenv("INPUT_PROMPT"),
		Skill:                  os.Getenv("INPUT_SKILL"),
		AdditionalInstructions: os.Getenv("INPUT_ADDITIONAL_INSTRUCTIONS"),
		AssessmentCriteria:     os.Getenv("INPUT_ASSESSMENT_CRITERIA"),
		BlockedPaths:           config.ParseBlockedPaths(os.Getenv("INPUT_BLOCKED_PATHS")),
		FooterType:             footerType,
	}
	if cfg.Prompt == "" && cfg.Skill == "" {
		return fmt.Errorf("at least one of 'prompt' or 'skill' must be provided")
	}
	tmpDir, err := ensureTmpDir()
	if err != nil {
		return err
	}
	path, err := prompt.Build(cfg, tmpDir)
	if err != nil {
		return err
	}
	action.SetOutput("prompt_file", path)
	return nil
}

func runPromptIssue() error {
	result := prompt.BuildIssuePrompt(
		os.Getenv("INPUT_PROMPT"),
		os.Getenv("INPUT_ISSUE_PROMPT_TEMPLATE"),
		os.Getenv("ISSUE_NUMBER"),
		os.Getenv("ISSUE_TITLE"),
		os.Getenv("ISSUE_BODY"),
	)
	action.SetOutputMultiline("prompt", result)
	return nil
}

func runComment(ctx context.Context) error {
	token := os.Getenv("GITHUB_TOKEN_INPUT")
	issueStr := os.Getenv("ISSUE_NUMBER")
	commentType := os.Getenv("COMMENT_TYPE")
	if token == "" || issueStr == "" || commentType == "" {
		return fmt.Errorf("GITHUB_TOKEN_INPUT, ISSUE_NUMBER, and COMMENT_TYPE are required")
	}

	ghClient := &github.GithubClient{Token: token}
	repo := os.Getenv("GITHUB_REPOSITORY")
	issue, _ := strconv.Atoi(issueStr)

	var body string
	switch commentType {
	case "skipped":
		summary := os.Getenv("SUMMARY")
		sanitized := sanitizeForCodeBlock(summary)
		body = fmt.Sprintf("Auto-solver assessed this issue but determined it is not suitable for automated resolution.\n\n```\n%s\n```", sanitized)
	case "success":
		prURL := os.Getenv("PR_URL")
		if prURL == "" {
			return fmt.Errorf("PR_URL is required for success comment")
		}
		body = fmt.Sprintf("Auto-solver has created a draft PR: %s\n\nPlease review the changes carefully before approving.", prURL)
	case "failed":
		body = "Auto-solver attempted to fix this issue but was unable to complete the implementation.\n\nThis issue may require human intervention."
	default:
		return fmt.Errorf("unknown comment type: %s", commentType)
	}

	return ghClient.CreateComment(ctx, repo, issue, body)
}

func runLabelRemove(ctx context.Context) error {
	token := os.Getenv("GITHUB_TOKEN_INPUT")
	issueStr := os.Getenv("ISSUE_NUMBER")
	if token == "" || issueStr == "" {
		return fmt.Errorf("GITHUB_TOKEN_INPUT and ISSUE_NUMBER are required")
	}
	label := envOrDefault("TRIGGER_LABEL", "autosolve")
	repo := os.Getenv("GITHUB_REPOSITORY")

	issue, _ := strconv.Atoi(issueStr)
	ghClient := &github.GithubClient{Token: token}
	return ghClient.RemoveLabel(ctx, repo, issue, label)
}

func ensureTmpDir() (string, error) {
	dir := os.Getenv("AUTOSOLVE_TMPDIR")
	if dir != "" {
		return dir, nil
	}
	dir, err := os.MkdirTemp("", "autosolve_*")
	if err != nil {
		return "", fmt.Errorf("creating temp dir: %w", err)
	}
	os.Setenv("AUTOSOLVE_TMPDIR", dir)
	return dir, nil
}

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// sanitizeForCodeBlock strips HTML tags and escapes triple backticks so the
// text can safely be placed inside a markdown code fence.
func sanitizeForCodeBlock(s string) string {
	var b strings.Builder
	inTag := false
	for _, c := range s {
		if c == '<' {
			inTag = true
			continue
		}
		if c == '>' && inTag {
			inTag = false
			continue
		}
		if !inTag {
			b.WriteRune(c)
		}
	}
	return strings.ReplaceAll(b.String(), "```", "` ` `")
}
