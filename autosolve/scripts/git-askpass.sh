#!/bin/sh
# GIT_ASKPASS script for fork authentication. Reads credentials from
# environment variables so the token is never written to disk.
set -e

if [ -z "$GIT_USER" ] || [ -z "$GIT_PASSWORD" ]; then
  echo "error: GIT_USER and GIT_PASSWORD must be set" >&2
  exit 1
fi

case "$1" in
  Username*) echo "$GIT_USER" ;;
  Password*) echo "$GIT_PASSWORD" ;;
esac
