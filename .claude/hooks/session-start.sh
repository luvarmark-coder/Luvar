#!/bin/bash
# Makes playwright-cli available to the playwright-cli skill, locally and in Claude Code cloud sessions.
set -euo pipefail

cd "$CLAUDE_PROJECT_DIR"

if [ ! -x node_modules/.bin/playwright-cli ]; then
  npm install --no-audit --no-fund >&2
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$CLAUDE_PROJECT_DIR/node_modules/.bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
  # Cloud containers ship Chromium but not Google Chrome, which playwright-cli uses by default.
  if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && [ -x /opt/pw-browsers/chromium ]; then
    echo 'export PLAYWRIGHT_MCP_BROWSER=chromium' >> "$CLAUDE_ENV_FILE"
    echo 'export PLAYWRIGHT_MCP_EXECUTABLE_PATH=/opt/pw-browsers/chromium' >> "$CLAUDE_ENV_FILE"
  fi
fi
