#!/usr/bin/env bash
# VoiceStudio installer wrapper for macOS / Linux.
#
#   install.sh                 latest stable desktop app (official installer)
#   install.sh --version X.Y.Z specific release
#   install.sh --docker [--gpu|--rocm] [--port 3900]   headless backend in Docker
#   install.sh --source [--dir ~/VoiceStudio]          developer checkout (bun run dev)
#   install.sh --uninstall     remove the app, keep user data
#   install.sh --check         only inspect the machine, install nothing
set -euo pipefail

MODE=app; VERSION=""; GPU=""; PORT=3900; DIR="$HOME/VoiceStudio"
REPO=https://github.com/debpalash/VoiceStudio
IMAGE=ghcr.io/debpalash/voicestudio

while [ $# -gt 0 ]; do
  case "$1" in
    --docker) MODE=docker ;;
    --source) MODE=source ;;
    --uninstall) MODE=uninstall ;;
    --check) MODE=check ;;
    --gpu) GPU=cuda ;;
    --rocm) GPU=rocm ;;
    --version) VERSION="$2"; shift ;;
    --port) PORT="$2"; shift ;;
    --dir) DIR="$2"; shift ;;
    -h|--help) sed -n 2,10p "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

inspect() {
  say "Device"
  echo "  OS:   $(uname -s) $(uname -r)  arch: $(uname -m)"
  if [ "$(uname -s)" = Darwin ]; then
    echo "  CPU:  $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
    echo "  RAM:  $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
    [ "$(uname -m)" = arm64 ] && echo "  GPU:  Apple Silicon (MPS)" \
      || warn "Intel Mac: app UI only, needs a remote backend (run --docker on a Linux/GPU box)"
  else
    echo "  RAM:  $(awk '/MemTotal/{printf "%d GB", $2/1048576}' /proc/meminfo)"
    if have nvidia-smi; then
      echo "  GPU:  $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | head -1) (CUDA)"
    elif [ -e /dev/kfd ]; then echo "  GPU:  AMD (ROCm device present)"
    else echo "  GPU:  none detected -> CPU mode (slower, ~5 GB disk)"; fi
  fi
  echo "  Free disk in \$HOME: $(df -h "$HOME" | awk 'NR==2{print $4}') (need >= 10 GB)"
  if have curl && curl -fsS -m 3 "http://localhost:$PORT/health" >/dev/null 2>&1; then
    say "A VoiceStudio backend is already running on :$PORT"
    curl -fsS "http://localhost:$PORT/health"; echo
    ALREADY=1
  fi
}

ALREADY=0
inspect
[ "$MODE" = check ] && exit 0

case "$MODE" in
  app|uninstall)
    if [ "$ALREADY" = 1 ] && [ "$MODE" = app ] && [ -z "$VERSION" ]; then
      say "Already installed and running - nothing to do. Use --version X.Y.Z to change version."
      exit 0
    fi
    have curl || { warn "curl is required"; exit 1; }
    ARGS=()
    [ -n "$VERSION" ] && ARGS+=(--version "$VERSION")
    [ "$MODE" = uninstall ] && ARGS+=(--uninstall)
    say "Running the official installer (https://voicestudio.sh/install) ${ARGS[*]:-}"
    if ! curl -fsSL https://voicestudio.sh/install | sh -s -- ${ARGS[@]+"${ARGS[@]}"}; then
      warn "Official installer unreachable. Fallback: download the package manually from"
      warn "  $REPO/releases/latest"
      warn "  macOS: VoiceStudio-Electron-*-mac-arm64.dmg  |  Linux: *-linux-x64.AppImage or .deb"
      exit 1
    fi
    say "Done. Launch VoiceStudio, finish first-run setup, then run: python3 \"$(dirname "$0")/vs.py\" doctor"
    ;;

  docker)
    have docker || { warn "Docker is not installed: https://docs.docker.com/get-docker/"; exit 1; }
    [ "$(uname -m)" = x86_64 ] || warn "Images are linux/amd64 only; on ARM add --platform linux/amd64 (emulated, slow)."
    TAG=stable; GPUFLAGS=()
    case "$GPU" in
      cuda) GPUFLAGS=(--gpus all) ;;
      rocm) TAG=stable-rocm; GPUFLAGS=(--device /dev/kfd --device /dev/dri) ;;
    esac
    if docker ps -a --format '{{.Names}}' | grep -qx omnivoice; then
      say "Container 'omnivoice' exists - starting it (data volume is kept)"
      docker start omnivoice
    else
      KEYFILE="$HOME/.voicestudio_api_key"
      if [ ! -s "$KEYFILE" ]; then
        umask 077
        python3 -c 'import secrets; print(secrets.token_urlsafe(32))' > "$KEYFILE"
      fi
      say "Admin API key stored in $KEYFILE (the web UI asks for it once)"
      docker pull "$IMAGE:$TAG"
      docker run -d --name omnivoice ${GPUFLAGS[@]+"${GPUFLAGS[@]}"} \
        -p "127.0.0.1:$PORT:3900" \
        -e OMNIVOICE_API_KEY="$(cat "$KEYFILE")" \
        -v omnivoice-data:/app/omnivoice_data \
        --restart unless-stopped \
        "$IMAGE:$TAG"
    fi
    say "Waiting for http://localhost:$PORT/health (first start can take minutes)"
    for _ in $(seq 1 120); do
      curl -fsS -m 3 "http://localhost:$PORT/health" && { echo; break; }
      sleep 5
    done
    say "Open http://localhost:$PORT in a browser. Logs: docker logs -f omnivoice"
    ;;

  source)
    for t in git bun uv node; do have "$t" || warn "missing $t (need git, Node 22+, bun, uv)"; done
    have git && have bun || exit 1
    if [ -d "$DIR/.git" ]; then
      say "Existing checkout at $DIR - updating (git pull --ff-only)"
      git -C "$DIR" pull --ff-only
    else
      git clone --depth 1 "$REPO.git" "$DIR"
    fi
    cd "$DIR"
    bun install
    bun run setup:api
    say "Ready. Start with: cd \"$DIR\" && bun run dev   (Electron starts and supervises the backend)"
    ;;
esac
