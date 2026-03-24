#!/usr/bin/env bash
set -euo pipefail

# Cross-compile the autosolve binary for linux/amd64 (GitHub Actions runners).
# The resulting binary is committed to the repo so the action doesn't need
# Go installed at runtime.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTDIR="bin"
mkdir -p "$OUTDIR"

echo "Building autosolve for linux/amd64..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -o "$OUTDIR/autosolve-linux-amd64" ./cmd/autosolve

echo "Built $OUTDIR/autosolve-linux-amd64"
ls -lh "$OUTDIR/autosolve-linux-amd64"
