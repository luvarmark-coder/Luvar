#!/bin/bash
# SessionStart hook: make `markitdown` available in every session.
#
# The remote container is ephemeral, so the tool has to be re-installed on each
# cold start. Locally the install persists and this script no-ops in ~50ms.
# Never fails the session: every step is best-effort and the script always
# exits 0.
set -uo pipefail

LOCAL_BIN="$HOME/.local/bin"
export PATH="$LOCAL_BIN:$PATH"

# Persist PATH for the rest of the session (CLAUDE_ENV_FILE is only set when
# this runs as a real hook, not when invoked by hand).
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$LOCAL_BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# --- markitdown ------------------------------------------------------------
# Note: `markitdown --version` costs ~10s (it imports onnxruntime/pandas at
# startup), so the already-installed path must not call it.
if command -v markitdown >/dev/null 2>&1; then
  echo "markitdown: ready ($(command -v markitdown))"
else
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
    export PATH="$LOCAL_BIN:$PATH"
  fi

  if command -v uv >/dev/null 2>&1; then
    uv tool install 'markitdown[all]' >/dev/null 2>&1
  elif command -v pipx >/dev/null 2>&1; then
    pipx install 'markitdown[all]' >/dev/null 2>&1
  fi

  if command -v markitdown >/dev/null 2>&1; then
    echo "markitdown: installed ($(command -v markitdown))"
  else
    echo "markitdown: install failed - use the 'markitdown' skill to retry on demand"
  fi
fi

# --- ffmpeg (optional; only needed for audio/video input) ------------------
# Without it markitdown warns on every run and cannot decode audio at all.
if ! command -v ffmpeg >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y --no-install-recommends ffmpeg >/dev/null 2>&1
fi

exit 0
