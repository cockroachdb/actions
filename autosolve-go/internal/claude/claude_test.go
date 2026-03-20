package claude

import (
	"encoding/json"
	"os"
	"testing"
)

func TestExtractResult_Success(t *testing.T) {
	f := writeJSON(t, claudeOutput{
		Type:      "result",
		Result:    "Analysis complete.\n\nIMPLEMENTATION_RESULT - SUCCESS",
		SessionID: "sess-123",
	})

	text, positive, err := ExtractResult(f, "IMPLEMENTATION_RESULT")
	if err != nil {
		t.Fatal(err)
	}
	if !positive {
		t.Error("expected positive result")
	}
	if text == "" {
		t.Error("expected non-empty text")
	}
}

func TestExtractResult_Failed(t *testing.T) {
	f := writeJSON(t, claudeOutput{
		Type:   "result",
		Result: "Could not fix it.\n\nIMPLEMENTATION_RESULT - FAILED",
	})

	text, positive, err := ExtractResult(f, "IMPLEMENTATION_RESULT")
	if err != nil {
		t.Fatal(err)
	}
	if positive {
		t.Error("expected negative result")
	}
	if text == "" {
		t.Error("expected non-empty text")
	}
}

func TestExtractResult_Proceed(t *testing.T) {
	f := writeJSON(t, claudeOutput{
		Type:   "result",
		Result: "This looks good.\n\nASSESSMENT_RESULT - PROCEED",
	})

	_, positive, err := ExtractResult(f, "ASSESSMENT_RESULT")
	if err != nil {
		t.Fatal(err)
	}
	if !positive {
		t.Error("expected positive (PROCEED)")
	}
}

func TestExtractResult_Skip(t *testing.T) {
	f := writeJSON(t, claudeOutput{
		Type:   "result",
		Result: "Too complex.\n\nASSESSMENT_RESULT - SKIP",
	})

	_, positive, err := ExtractResult(f, "ASSESSMENT_RESULT")
	if err != nil {
		t.Fatal(err)
	}
	if positive {
		t.Error("expected negative (SKIP)")
	}
}

func TestExtractResult_NoMarker(t *testing.T) {
	f := writeJSON(t, claudeOutput{
		Type:   "result",
		Result: "Some random output without a marker",
	})

	_, _, err := ExtractResult(f, "IMPLEMENTATION_RESULT")
	if err == nil {
		t.Error("expected error when marker is missing")
	}
}

func TestExtractResult_EmptyResult(t *testing.T) {
	f := writeJSON(t, claudeOutput{
		Type:   "result",
		Result: "",
	})

	_, _, err := ExtractResult(f, "IMPLEMENTATION_RESULT")
	if err == nil {
		t.Error("expected error for empty result")
	}
}

func TestExtractSessionID(t *testing.T) {
	f := writeJSON(t, claudeOutput{
		Type:      "result",
		Result:    "done",
		SessionID: "sess-abc-123",
	})

	id := ExtractSessionID(f)
	if id != "sess-abc-123" {
		t.Errorf("expected session ID 'sess-abc-123', got %q", id)
	}
}

func TestExtractSessionID_Missing(t *testing.T) {
	f := writeJSON(t, claudeOutput{
		Type:   "result",
		Result: "done",
	})

	id := ExtractSessionID(f)
	if id != "" {
		t.Errorf("expected empty session ID, got %q", id)
	}
}

func TestExtractResult_FileNotFound(t *testing.T) {
	_, _, err := ExtractResult("/nonexistent/file.json", "IMPLEMENTATION_RESULT")
	if err == nil {
		t.Error("expected error for missing file")
	}
}

func writeJSON(t *testing.T, v interface{}) string {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	f, err := os.CreateTemp(t.TempDir(), "claude_*.json")
	if err != nil {
		t.Fatal(err)
	}
	f.Write(data)
	f.Close()
	return f.Name()
}
