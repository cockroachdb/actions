.PHONY: build build-linux test clean

# Local dev binary
build:
	go build -o autosolve ./cmd/autosolve

# Cross-compile for GitHub Actions (linux/amd64), same as build.sh
build-linux:
	./build.sh

test:
	go test ./... -count=1

clean:
	rm -f autosolve bin/autosolve-linux-amd64
