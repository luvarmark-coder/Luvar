#!/usr/bin/env bash
# Ensure the `goclone` binary is available, installing it if needed.
#
# Prints the absolute path of the binary on stdout (and nothing else on stdout),
# so callers can do:  GOCLONE="$(scripts/install.sh)"
# Progress/диагностика goes to stderr.
#
# Install order: existing binary -> `go install` -> homebrew -> build from source.
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }

MODULE="github.com/goclone-dev/goclone"
CMD_PATH="${MODULE}/cmd/goclone@latest"

gobin() {
  if command -v go >/dev/null 2>&1; then
    local b
    b="$(go env GOBIN)"
    [ -n "$b" ] || b="$(go env GOPATH)/bin"
    printf '%s' "$b"
  fi
}

find_existing() {
  if command -v goclone >/dev/null 2>&1; then
    command -v goclone
    return 0
  fi
  local b
  b="$(gobin)"
  if [ -n "$b" ] && [ -x "$b/goclone" ]; then
    printf '%s\n' "$b/goclone"
    return 0
  fi
  return 1
}

if p="$(find_existing)"; then
  log "goclone already installed: $p"
  printf '%s\n' "$p"
  exit 0
fi

# --- Attempt 1: go install (works on any platform with Go >= 1.20) ------------
if command -v go >/dev/null 2>&1; then
  log "Installing via: go install ${CMD_PATH}"
  if go install "${CMD_PATH}" >&2; then
    if p="$(find_existing)"; then
      log "Installed: $p"
      printf '%s\n' "$p"
      exit 0
    fi
  fi
  log "go install did not produce a binary, trying other methods."
fi

# --- Attempt 2: homebrew ------------------------------------------------------
if command -v brew >/dev/null 2>&1; then
  log "Installing via homebrew"
  if brew tap goclone-dev/goclone >&2 && brew install goclone >&2; then
    if p="$(find_existing)"; then
      log "Installed: $p"
      printf '%s\n' "$p"
      exit 0
    fi
  fi
  log "homebrew install failed, trying source build."
fi

# --- Attempt 3: build from source --------------------------------------------
if command -v go >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  src="$(mktemp -d)"
  log "Building from source in $src"
  git clone --depth 1 "https://${MODULE}.git" "$src/goclone" >&2
  dest="$(gobin)"
  mkdir -p "$dest"
  (cd "$src/goclone" && go build -o "$dest/goclone" ./cmd/goclone) >&2
  rm -rf "$src"
  if [ -x "$dest/goclone" ]; then
    log "Built: $dest/goclone"
    printf '%s\n' "$dest/goclone"
    exit 0
  fi
fi

log "ERROR: could not install goclone. Install Go (>= 1.20) from https://go.dev/dl/ and re-run,"
log "or install manually: go install ${CMD_PATH}"
exit 1
