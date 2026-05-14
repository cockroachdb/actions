// Package git abstracts git CLI operations behind an interface for testability.
package git

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// Client defines git operations needed by autosolve.
type Client interface {
	Diff(args ...string) (string, error)
	LsFiles(args ...string) (string, error)
	Config(args ...string) error
	Remote(args ...string) (string, error)
	Checkout(args ...string) error
	Add(args ...string) error
	Commit(message string) error
	Push(args ...string) error
	BranchExists(remoteURL, branch string) (bool, error)
	RevParse(args ...string) (string, error)
	ResetHead() error
}

// CLIClient implements Client by shelling out to the git binary.
//
// AuthEnv carries env vars (typically GIT_ASKPASS plus credentials)
// applied to remote-contacting commands (Push, BranchExists). Set this
// only when every remote-contacting call should use the same credentials
// — the env is not URL-scoped, so adding a new call site that targets a
// different remote would silently send these creds there. Local-only
// commands ignore AuthEnv entirely (git only invokes the askpass when
// challenged for credentials).
type CLIClient struct {
	AuthEnv []string
}

// NewAuthEnv builds the env block consumed by both CLIClient.AuthEnv
// and scripts/git-askpass.sh: GIT_ASKPASS points at the askpass script,
// GIT_USER/GIT_PASSWORD carry the credentials it returns,
// GIT_TERMINAL_PROMPT=0 prevents git from falling back to an interactive
// prompt if anything goes wrong.
//
// The askpass script lives under SCRIPTS_DIR, an env var the autosolve
// action sets before invoking the binary (and config validates is present).
func NewAuthEnv(user, token string) []string {
	askpass := filepath.Join(os.Getenv("SCRIPTS_DIR"), "git-askpass.sh")
	return []string{
		"GIT_ASKPASS=" + askpass,
		"GIT_USER=" + user,
		"GIT_PASSWORD=" + token,
		"GIT_TERMINAL_PROMPT=0",
	}
}

func (c *CLIClient) Diff(args ...string) (string, error) {
	return c.output(append([]string{"diff"}, args...)...)
}

func (c *CLIClient) LsFiles(args ...string) (string, error) {
	return c.output(append([]string{"ls-files"}, args...)...)
}

func (c *CLIClient) Config(args ...string) error {
	return c.run(append([]string{"config"}, args...)...)
}

func (c *CLIClient) Remote(args ...string) (string, error) {
	return c.output(append([]string{"remote"}, args...)...)
}

func (c *CLIClient) Checkout(args ...string) error {
	return c.run(append([]string{"checkout"}, args...)...)
}

func (c *CLIClient) Add(args ...string) error {
	return c.run(append([]string{"add"}, args...)...)
}

func (c *CLIClient) Commit(message string) error {
	cmd := exec.Command("git", "commit", "--message", message)
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func (c *CLIClient) Push(args ...string) error {
	cmd := exec.Command("git", append([]string{"push"}, args...)...)
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	if len(c.AuthEnv) > 0 {
		cmd.Env = append(os.Environ(), c.AuthEnv...)
	}
	return cmd.Run()
}

// BranchExists reports whether the named branch exists on the given
// remote URL. Implemented via `git ls-remote <url> refs/heads/<branch>`,
// which prints "<sha>\t<refname>" for a match and nothing for a miss
// (exit 0 in both cases; nonzero only on network/auth/URL errors).
func (c *CLIClient) BranchExists(remoteURL, branch string) (bool, error) {
	cmd := exec.Command("git", "ls-remote", remoteURL, "refs/heads/"+branch)
	cmd.Stderr = os.Stderr
	if len(c.AuthEnv) > 0 {
		cmd.Env = append(os.Environ(), c.AuthEnv...)
	}
	out, err := cmd.Output()
	if err != nil {
		return false, err
	}
	return strings.TrimSpace(string(out)) != "", nil
}

func (c *CLIClient) RevParse(args ...string) (string, error) {
	return c.output(append([]string{"rev-parse"}, args...)...)
}

func (c *CLIClient) ResetHead() error {
	cmd := exec.Command("git", "reset", "HEAD")
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func (c *CLIClient) run(args ...string) error {
	cmd := exec.Command("git", args...)
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func (c *CLIClient) output(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

// ChangedFiles returns a deduplicated, sorted list of all changed files
// (unstaged, staged, and untracked) using the given git client.
func ChangedFiles(g Client) ([]string, error) {
	seen := make(map[string]bool)

	unstaged, err := g.Diff("--name-only")
	if err != nil {
		return nil, fmt.Errorf("git diff: %w", err)
	}
	addLines(seen, unstaged)

	staged, err := g.Diff("--name-only", "--cached")
	if err != nil {
		return nil, fmt.Errorf("git diff --cached: %w", err)
	}
	addLines(seen, staged)

	untracked, err := g.LsFiles("--others", "--exclude-standard")
	if err != nil {
		return nil, fmt.Errorf("git ls-files: %w", err)
	}
	addLines(seen, untracked)

	files := make([]string, 0, len(seen))
	for f := range seen {
		files = append(files, f)
	}
	sort.Strings(files)
	return files, nil
}

func addLines(seen map[string]bool, output string) {
	for _, line := range strings.Split(output, "\n") {
		if line != "" {
			seen[line] = true
		}
	}
}
