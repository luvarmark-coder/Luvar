# VoiceStudio REST API cheat-sheet

Base: `http://localhost:3900` (loopback needs no auth). Remote/Docker: add
`-H "Authorization: Bearer $OMNIVOICE_API_KEY"` (or `X-OmniVoice-Pin` for LAN share).
The running backend is the source of truth: `GET /openapi.json`, Swagger at `/docs`.
`python3 scripts/vs.py openapi dub` lists live paths matching "dub".

## Status & models

| Method | Path | Notes |
|---|---|---|
| GET | `/health` | `{"status":"ok","device":"cuda","version":"0.5.7"}`; 503 `status: starting` while booting |
| GET | `/models` | `{"models":[{"repo_id","installed","size_gb","license_info",…}], "disk_free_gb"}` |
| POST | `/models/install` | `{"repo_id":"k2-fsa/OmniVoice"}` — only after consent |
| GET | `/models/install/status` | `{"jobs":[{"repo_id","state":"downloading|failed",…}]}`; empty = done, then confirm via `/models` |
| GET | `/engines`, `/engines/tts`, `/engines/asr` | engine registry & capabilities |

## OpenAI-compatible (`/v1`)

```sh
# Text to speech (input ≤ 4096 chars; voice = profile id, unique profile name or OpenAI alias)
curl --fail-with-body http://localhost:3900/v1/audio/speech \
  -H 'Content-Type: application/json' \
  -d '{"model":"tts-1","voice":"<profile_id>","input":"Привет!","response_format":"wav","language":"ru"}' \
  -o out.wav

# Voices: {"voices":[{"voice_id","name","type":"profile|openai_alias","language"}],"engines":[…]}
curl http://localhost:3900/v1/audio/voices

# Transcription: response_format text | json | verbose_json | srt | vtt
curl --fail-with-body http://localhost:3900/v1/audio/transcriptions \
  -F file=@clip.wav -F model=whisper-1 -F response_format=srt

# Translate speech to English text
curl http://localhost:3900/v1/audio/translations -F file=@clip.wav -F model=whisper-1
```

Speech extras (VoiceStudio extensions): `speed` 0.25–4, `instructions`/`instruct`,
`seed`, `duration`, `num_step` (16 default, 32 = quality), `guidance_scale` (2.0),
`stream_format: "audio"|"sse"`. Formats: `mp3` (default), `opus`, `aac`, `flac`, `wav`,
`pcm` (raw 24 kHz s16le mono).

Works with the OpenAI SDK:

```python
from openai import OpenAI
c = OpenAI(base_url="http://localhost:3900/v1", api_key="local")
c.audio.speech.create(model="tts-1", voice="<profile_id>", input="Hi").write_to_file("hi.mp3")
```

## Voice profiles (native)

| Method | Path | Notes |
|---|---|---|
| GET | `/profiles` | all profiles |
| POST | `/profiles` | multipart: `name`, `kind=clone` + `ref_audio` file (+ `ref_text`, `language`, `instruct`) **or** `kind=design` + `vd_states` JSON |
| GET/PUT/DELETE | `/profiles/{id}` | read / update / delete (confirm before delete) |
| GET | `/profiles/{id}/audio` | reference audio |
| POST | `/design/describe` | `{"description":"…"}` → `{attrs, instruct, matched, unmatched}` (saves nothing) |

```sh
# Clone (user must own the voice / have consent)
curl -F name="My voice" -F kind=clone -F ref_audio=@me.wav -F ref_text="what I said" \
     -F language=Auto http://localhost:3900/profiles
```

## Native generation

`POST /generate` (multipart) — no 4096-char limit, sentence chunking with crossfade:
`text`, `profile_id`, `language`, `instruct`, `speed`, `seed`, `num_step`,
`guidance_scale`, `effect_preset` (default `broadcast`), `wav_bits` 16/24/32,
`engine`, `max_chunk_chars` (800), `crossfade_ms` (50), `pronounce` (true).
History: `GET /history`, `DELETE /history/{id}`.

## Dubbing pipeline (native, evolves — confirm in /openapi.json)

1. `POST /dub/upload` multipart `video=@file`, `input_type=video|audio`, `source_lang` → 202 `{job_id, task_id}`;
   watch `GET /tasks/stream/{task_id}` (SSE) until `ready`. Or `POST /dub/ingest-url` for a link.
2. `POST /dub/transcribe/{job_id}` (or `/dub/import-srt/{job_id}`) — speech to segments.
3. `POST /dub/translate` — translate segments (cloud providers only with user's choice).
4. `POST /dub/generate/{job_id}` — synthesize segments with assigned voices; `POST /dub/qc/{job_id}` to check.
5. Export: `GET /dub/download/{job_id}` (video), `/dub/download-audio/{job_id}`,
   `/dub/download-mp3/{job_id}`, `/dub/srt/{job_id}`, `/dub/vtt/{job_id}`, `/dub/export-stems/{job_id}`.
6. Abort: `POST /dub/abort/{job_id}`. History: `GET /dub/history`.

Jobs: `GET /jobs`, `GET /jobs/{id}`, `GET /jobs/{id}/events`; cancel task `POST /tasks/cancel/{task_id}`.
Other routers: stories/audiobook, batch, longform jobs, pronunciation dictionary,
glossary, voice conversion, watermark, projects, personas.
