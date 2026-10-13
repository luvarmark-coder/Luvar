# Installing VoiceStudio

Upstream: https://github.com/debpalash/VoiceStudio · releases: `/releases/latest`.
Current line: 0.5.x (Electron desktop app + Python backend on port 3900).

## Pick a method

| Situation | Command | Result |
|---|---|---|
| macOS (Apple Silicon) / Linux desktop | `bash scripts/install.sh` | official installer → desktop app |
| Specific version | `bash scripts/install.sh --version 0.5.7` | pinned release |
| Windows 10/11 x64 | `powershell -ExecutionPolicy Bypass -File scripts\install.ps1` | official installer → `.exe` app |
| Headless Linux server, CPU | `bash scripts/install.sh --docker` | container `omnivoice`, web UI on :3900 |
| Headless, NVIDIA GPU | `bash scripts/install.sh --docker --gpu` | needs NVIDIA Container Toolkit |
| Headless, AMD GPU | `bash scripts/install.sh --docker --rocm` | `:stable-rocm` image |
| Developer preview from `main` | `bash scripts/install.sh --source` | git checkout + `bun run dev` |
| Only inspect the machine | `bash scripts/install.sh --check` | no changes |
| Remove app, keep data | `bash scripts/install.sh --uninstall` | |

Manual alternative: download from Releases — macOS `.dmg`, Windows `.exe`,
Linux `.AppImage` (`chmod +x` then run) or `.deb` (`sudo apt install ./file.deb`).
Asset names: `VoiceStudio-Electron-<version>-<os>-<arch>.<ext>`.

The official one-liners (what the wrappers call):

```sh
curl -fsSL https://voicestudio.sh/install | sh                  # macOS / Linux
curl -fsSL https://voicestudio.sh/install | sh -s -- --version X.Y.Z
curl -fsSL https://voicestudio.sh/install | sh -s -- --main     # build main (needs git, Node 22+, bun, Rust)
curl -fsSL https://voicestudio.sh/install | sh -s -- --uninstall
irm https://voicestudio.sh/install | iex                        # Windows PowerShell
```

## Hardware

| Hardware | Support |
|---|---|
| NVIDIA GPU (Windows / Linux) | CUDA acceleration |
| Apple Silicon | Metal (MPS) |
| AMD GPU (Linux, Docker) | ROCm image |
| No GPU | works on CPU, slower; CPU PyTorch build (~5 GB disk) |
| Windows on ARM | experimental, CPU only |
| Intel Mac | UI only — connect to a remote backend |

Disk: ~10 GB for app + Python env + models. The default OmniVoice model is ~2.3 GB.
Docker images are `linux/amd64` only.

## First run

1. The app bootstraps Python, ffmpeg/ffprobe, yt-dlp automatically.
2. It shows an analytics consent prompt (opt-in, Yes/No). **Leave this to the user.**
3. It offers model setup. State size + license, get consent, then install
   (or `vs.py install-model <repo_id> --yes`).
4. Data lives in `omnivoice_data/` (voices, projects, settings) — preserved across
   updates and uninstall.

## Docker details

- Image: `ghcr.io/debpalash/voicestudio:stable` (mirror `palashdeb/omnivoice-studio`).
  `:latest` = rolling preview from main; pin `:stable` or `:X.Y.Z` for production.
- Docker needs an admin key (`OMNIVOICE_API_KEY`); the wrapper creates
  `~/.voicestudio_api_key` (mode 600). The web UI asks for it once. For CLI calls from
  outside the container: `export OMNIVOICE_API_KEY=$(cat ~/.voicestudio_api_key)`.
- Data volume: `omnivoice-data:/app/omnivoice_data`.
- Update: `docker pull ghcr.io/debpalash/voicestudio:stable && docker rm -f omnivoice && bash scripts/install.sh --docker`
  (the named volume keeps your data).
- Disable analytics completely: add `-e OMNIVOICE_ANALYTICS_DISABLED=1`.

## From source

Prereqs: git, Node.js 22+, bun, uv (Python), ffmpeg recommended.

```sh
git clone https://github.com/debpalash/VoiceStudio.git && cd VoiceStudio
bun install
bun run setup:api   # prepares the Python backend
bun run dev         # Electron starts and supervises the backend
```

Do not start a second backend next to the app.

## Verification checklist (report all of these)

- [ ] `python3 scripts/vs.py health` → `status: ok`, real `device` (cuda / mps / cpu)
- [ ] `python3 scripts/vs.py doctor` → at least one model installed
- [ ] `python3 scripts/vs.py speak "Test" -o test.wav` → non-empty WAV with duration > 0
- [ ] Installed version, engine, device, data location, output path, how to reopen the app
