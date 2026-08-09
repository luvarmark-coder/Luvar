#!/usr/bin/env bash
# Clone one or more pages with goclone into a chosen output directory.
#
# Usage:
#   clone.sh [-d OUTPUT_DIR] [-u USER_AGENT] [-p PROXY] [-C COOKIES] [-n] URL [URL...]
#
# goclone always writes its project folder into the *current* working directory,
# named after the domain. This wrapper makes the destination explicit, installs
# the binary if it is missing, runs the offline fixup, and prints a summary of
# what actually landed on disk — the exit code alone does not tell you whether
# assets downloaded.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OUT_DIR="."
FIX=1
EXTRA=()

usage() {
  echo "usage: clone.sh [-d OUTPUT_DIR] [-u USER_AGENT] [-p PROXY] [-C COOKIES] [-n] URL [URL...]" >&2
  echo "  -n  skip the offline fixup (fix_offline.py)" >&2
}

while getopts ":d:u:p:C:nh" opt; do
  case "$opt" in
    d) OUT_DIR="$OPTARG" ;;
    u) EXTRA+=(--user_agent "$OPTARG") ;;
    p) EXTRA+=(--proxy_string "$OPTARG") ;;
    C) EXTRA+=(--cookie "$OPTARG") ;;
    n) FIX=0 ;;
    h) usage; exit 0 ;;
    \?) echo "unknown option -$OPTARG" >&2; usage; exit 2 ;;
    :) echo "option -$OPTARG needs a value" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

GOCLONE="$("$HERE/install.sh")"

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

cd "$OUT_DIR"
"$GOCLONE" "${EXTRA[@]}" "$@"

echo
echo "=== Result in $OUT_DIR ==="
for url in "$@"; do
  # goclone names the folder after the host, without scheme or path
  domain="${url#*://}"
  domain="${domain%%/*}"
  dir="$OUT_DIR/$domain"
  if [ -d "$dir" ]; then
    if [ "$FIX" -eq 1 ] && command -v python3 >/dev/null 2>&1; then
      python3 "$HERE/fix_offline.py" "$dir" || true
    fi
    files=$(find "$dir" -type f | wc -l | tr -d ' ')
    size=$(du -sh "$dir" | cut -f1)
    html_bytes=$(wc -c < "$dir/index.html" 2>/dev/null || echo 0)
    echo "$dir  ($files files, $size, index.html ${html_bytes} bytes)"
    if [ "$html_bytes" -lt 500 ]; then
      echo "  WARNING: index.html is nearly empty — the page is probably JS-rendered or blocked the request." >&2
    fi
  else
    echo "MISSING: expected $dir for $url" >&2
  fi
done
