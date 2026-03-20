// Package claude provides an interface for invoking the Claude CLI and
// parsing its JSON output.
package claude

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Runner invokes the Claude CLI.
type Runner interface {
	Run(ctx context.Context, opts RunOptions) (*Result, error)
}

// RunOptions configures a Claude CLI invocation.
type RunOptions struct {
	Model        string
	AllowedTools string
	MaxTurns     int
	PromptFile   string // path to prompt file (used as stdin on first attempt)
	Resume       string // session ID for --resume
	RetryPrompt  string // prompt text for retry attempts (used as stdin with --resume)
	OutputFile   string // path to write JSON output
}

// Result holds parsed Claude CLI output.
type Result struct {
	ResultText string
	SessionID  string
	ExitCode   int
}

// CLIRunner is the production Runner that shells out to the claude binary.
type CLIRunner struct{}

// Run executes the claude CLI with the given options.
func (r *CLIRunner) Run(ctx context.Context, opts RunOptions) (*Result, error) {
	args := []string{
		"--print",
		"--model", opts.Model,
		"--allowedTools", opts.AllowedTools,
		"--output-format", "json",
		"--max-turns", fmt.Sprintf("%d", opts.MaxTurns),
	}
	if opts.Resume != "" {
		args = append(args, "--resume", opts.Resume)
	}

	cmd := exec.CommandContext(ctx, "claude", args...)
	cmd.Stderr = os.Stderr

	// Set up stdin: either the prompt file or the retry prompt text
	if opts.Resume != "" && opts.RetryPrompt != "" {
		cmd.Stdin = strings.NewReader(opts.RetryPrompt)
	} else if opts.PromptFile != "" {
		f, err := os.Open(opts.PromptFile)
		if err != nil {
			return nil, fmt.Errorf("opening prompt file: %w", err)
		}
		defer f.Close()
		cmd.Stdin = f
	}

	// Capture stdout to output file
	outFile, err := os.Create(opts.OutputFile)
	if err != nil {
		return nil, fmt.Errorf("creating output file: %w", err)
	}
	defer outFile.Close()
	cmd.Stdout = outFile

	exitCode := 0
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			return nil, fmt.Errorf("running claude CLI: %w", err)
		}
	}

	// Parse the output
	result, err := parseOutput(opts.OutputFile)
	if err != nil {
		return &Result{ExitCode: exitCode}, nil
	}
	result.ExitCode = exitCode
	return result, nil
}

// ExtractResult extracts the result text from Claude JSON output and checks
// for the expected marker. Returns the result text and whether the marker
// was found with a positive outcome (PROCEED/SUCCESS).
func ExtractResult(outputFile, markerPrefix string) (text string, positive bool, err error) {
	text, err = extractResultText(outputFile)
	if err != nil {
		return "", false, err
	}

	if strings.Contains(text, markerPrefix+" - SUCCESS") || strings.Contains(text, markerPrefix+" - PROCEED") {
		return text, true, nil
	}
	if strings.Contains(text, markerPrefix+" - FAILED") || strings.Contains(text, markerPrefix+" - SKIP") {
		return text, false, nil
	}
	return text, false, fmt.Errorf("no valid %s marker found in output", markerPrefix)
}

// ExtractSessionID extracts the session ID from Claude JSON output.
func ExtractSessionID(outputFile string) string {
	result, err := parseOutput(outputFile)
	if err != nil {
		return ""
	}
	return result.SessionID
}

// claudeOutput represents the JSON structure from claude --print --output-format json.
type claudeOutput struct {
	Type      string `json:"type"`
	Result    string `json:"result"`
	SessionID string `json:"session_id"`
}

func parseOutput(path string) (*Result, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var out claudeOutput
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("parsing claude output: %w", err)
	}

	if out.Type != "result" {
		return nil, fmt.Errorf("unexpected output type: %s", out.Type)
	}

	return &Result{
		ResultText: out.Result,
		SessionID:  out.SessionID,
	}, nil
}

func extractResultText(path string) (string, error) {
	result, err := parseOutput(path)
	if err != nil {
		return "", err
	}
	if result.ResultText == "" {
		return "", fmt.Errorf("empty result text")
	}
	return result.ResultText, nil
}
