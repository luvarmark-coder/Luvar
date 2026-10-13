---
name: voicestudio
description: Install, run and drive VoiceStudio (github.com/debpalash/VoiceStudio) — a fully local, open-source ElevenLabs alternative for voice cloning, voice design, text-to-speech, transcription, video dubbing and audiobooks in 646 languages. Use when the user wants to install VoiceStudio, check that it works, generate speech, clone or design a voice, transcribe audio, dub a video, connect VoiceStudio to Claude/agents over MCP, or troubleshoot it. Triggers on "VoiceStudio", "OmniVoice", "клонировать голос", "озвучка", "синтез речи", "дубляж видео", "голосовой клон", "voice clone", "TTS locally".
---

# VoiceStudio skill

VoiceStudio is a desktop app (Electron) with a local Python backend. Everything runs on
the user's machine: the backend listens on `http://localhost:3900`, exposes an
OpenAI-compatible audio API under `/v1`, native endpoints (profiles, generation,
dubbing, models), and an MCP server at `/mcp/`.

This skill is self-contained (no 40 MB repo download needed). It contains:

| File | Use it for |
|---|---|
| `scripts/install.sh` | install on macOS / Linux (release app, Docker backend, or from source) |
| `scripts/install.ps1` | install on Windows |
| `scripts/vs.py` | stdlib-only CLI: health, voices, models, speak, transcribe, clone, design, dub, MCP config |
| `references/install.md` | platform notes, hardware table, verification checklist |
| `references/api.md` | REST endpoints with ready-to-run examples |
| `references/mcp.md` | connecting Claude Code / Cursor / Codex to VoiceStudio over MCP |
| `references/troubleshooting.md` | error → cause → fix table |

Run scripts by path, e.g. `python3 <skill-dir>/scripts/vs.py health`.
`vs.py` reads `VOICESTUDIO_URL` (default `http://localhost:3900`) and, for protected
deployments, `OMNIVOICE_API_KEY` or `OMNIVOICE_PIN`.

## Ground rules (always)

1. **Local-first.** Never send the user's audio, text or voices to a cloud service.
   Model downloads, cloud translation, LAN sharing and analytics happen only after the
   user's explicit yes. Never answer the app's first-run analytics prompt for them.
2. **Consent for voices.** Clone only voices the user owns or is authorized to use.
   Refuse to clone a third party's voice for impersonation or fraud.
3. **Ask before big downloads.** State model name, size and license, then install.
4. **Reuse, don't duplicate.** Reuse an existing install, backend, data folder
   (`omnivoice_data/`) and voice profiles. Never start a second backend.
5. **Never fake results.** Check HTTP status, probe the output file (size, duration,
   format) before calling it audio. Report real paths, durations, engine and device.
6. **Electron only.** The old Tauri build is archived — never install it.

## Workflow 1 — Install

1. Inspect the device: OS, CPU arch, GPU (`nvidia-smi`, Apple Silicon?), RAM/VRAM,
   free disk (need ≥ 5 GB CPU / ≥ 10 GB GPU), existing install (`vs.py health`).
2. If the backend already answers `/health`, **skip install** and go to Workflow 2.
3. Choose the method (details in `references/install.md`):
   - Desktop, macOS/Linux: `bash scripts/install.sh` (official release installer).
   - Desktop, Windows: `powershell -ExecutionPolicy Bypass -File scripts\install.ps1`.
   - Headless server / no desktop: `bash scripts/install.sh --docker [--gpu]`.
   - Developer preview: `bash scripts/install.sh --source` (git, bun, uv, Node 22+).
   - Intel Mac: app UI only — it needs a remote backend (Docker on a Linux/GPU box).
4. Launch the app (first run downloads ffmpeg and offers model setup — let the user
   decide on the model download).
5. Verify with `python3 scripts/vs.py doctor` and finish with a test clip (Workflow 2).
6. Report: version, engine, device (cuda / mps / cpu), data location, output file path,
   how to reopen the app.

## Workflow 2 — Check readiness and install a model

```sh
python3 scripts/vs.py health          # backend up? device?
python3 scripts/vs.py models          # installed / not installed engines
python3 scripts/vs.py install-model <repo_id>   # ONLY after user consent (size + license)
python3 scripts/vs.py voices          # saved voice profiles and their IDs
```

The default engine is OmniVoice (`k2-fsa/OmniVoice`, ~2.3 GB). `install-model` posts
`/models/install` and polls `/models/install/status` until `GET /models` reports
`"installed": true`; it stops on a `failed` job.

## Workflow 3 — Generate speech (TTS)

```sh
python3 scripts/vs.py speak "Привет! Это мой локальный голос." -o hello.wav \
    --voice <profile_id> --language ru
```

- `--voice` takes a discovered profile ID or name; without it the default voice is used.
- Long texts are fine: the backend chunks at sentence boundaries. For a file use
  `--text-file chapter.txt`.
- Formats: `wav` (default), `mp3`, `opus`, `flac`, `aac`, `pcm` (`--format`).
- Extras: `--speed 0.25–4.0`, `--instructions "calm, warm, slow"`, `--seed 42`.
- After generation the script prints size and WAV duration; check them before reporting.

## Workflow 4 — Clone a voice

Ask for confirmation that the user owns the voice / has consent. Need a clean 5–20 s
recording, one speaker, no music; transcript of the clip improves quality.

```sh
python3 scripts/vs.py clone "Моя озвучка" --audio me.wav --ref-text "текст записи" --language ru
python3 scripts/vs.py speak "Проверка клона" --voice "Моя озвучка" -o test.wav
```

## Workflow 5 — Design a voice from a description

```sh
python3 scripts/vs.py design "Рассказчик" --description "deep calm male narrator, middle-aged, British accent"
```

Uses the MCP `design_voice` tool if available, otherwise the `/profiles` endpoint with
`kind=design`. A description that maps to no attribute is refused — rephrase with
gender / age / pitch / style / accent words.

## Workflow 6 — Transcribe / subtitles

```sh
python3 scripts/vs.py transcribe interview.mp3 --format srt -o interview.srt
```

Formats: `text`, `json`, `verbose_json` (timestamps), `srt`, `vtt`. Translation to
English: add `--translate`.

## Workflow 7 — Dub a video

Dubbing is a multi-stage job: upload → (separate vocals / scenes) → transcribe →
translate → generate → export. `vs.py dub` runs the upload stage and prints the
`job_id`; the remaining stages are best done in the app's **Dubbing** workspace, or
through the native endpoints listed in `references/api.md` (always confirm request
schemas against the running backend's `/openapi.json` — they evolve between versions).
Keep the original media; deliver the dub as a separate file; translation finished ≠
dub rendered.

## Workflow 8 — Connect to Claude / agents (MCP)

```sh
python3 scripts/vs.py mcp-config claude-code   # prints .mcp.json snippet
```

Claude Code one-liner:
`claude mcp add --transport http voicestudio http://127.0.0.1:3900/mcp/ --header "X-OmniVoice-Client-Id: claude-code"`

MCP tools: `generate_speech`, `clone_voice`, `design_voice`, `describe_voice`,
`transcribe`, `list_voices`, `list_personalities`, `list_languages`, `check_health`.
See `references/mcp.md` (output modes, base path, per-agent voices, LAN/Docker).

## Errors

Distinguish: backend down (connection refused) · model missing (409/503 with model
hint) · unsupported capability (422) · auth (401/403 — never disable auth) · busy GPU
(429/503 + `Retry-After`) · timeout. Read the response body; fix the reported cause.
Full table: `references/troubleshooting.md`.

## Source

Upstream project: https://github.com/debpalash/VoiceStudio (AGPL-3.0). Docs:
`docs/install/*`, `docs/mcp.md`, `docs/api-auth.md` in that repo. Skill based on
upstream `skills/voicestudio/SKILL.md` (VoiceStudio 0.5.7, October 2026).
