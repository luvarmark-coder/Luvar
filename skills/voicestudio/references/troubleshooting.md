# Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Connection refused` on :3900 | app/container not running, or other port | start the app / `docker start omnivoice`; check `OMNIVOICE_PORT`; set `VOICESTUDIO_URL` |
| `/health` 503 `status: starting` | backend still booting (step shown) | wait, poll every 2–5 s |
| Speech call 409/503 mentioning model | engine model not installed | `vs.py models`, ask consent, `vs.py install-model <repo_id> --yes` |
| First generation very slow / timeout | model downloading inside request (~2.3 GB) or CPU mode | install model first; raise `OMNIVOICE_GENERATE_TIMEOUT_S`; CPU is several× slower |
| 429 "install failed recently" | cooldown after a failed download | wait the stated seconds; check network / HF reachability |
| Downloads fail in restricted networks | huggingface.co blocked | app falls back to hf-mirror.com probe; set HF endpoint/token in Settings |
| 401 / 403 | API key or PIN required (Docker, LAN, remote) | export `OMNIVOICE_API_KEY` / `OMNIVOICE_PIN`; never disable auth |
| 422 | unsupported parameter / capability for this engine, bad form field | read body; check `/openapi.json` and `/engines/tts` capabilities |
| 429/503 with `Retry-After` | GPU busy / queue full | wait `Retry-After`, don't spam retries |
| Output file is tiny / not playable | an error body was saved as audio | inspect file; vs.py refuses JSON responses |
| Bare `/mcp` returns 405 | older backend | use `/mcp/` with trailing slash |
| MCP "Invalid Host header" from Docker | DNS-rebinding guard | set `OMNIVOICE_MCP_ALLOWED_HOSTS` |
| `no matching manifest for linux/arm64` | images are amd64-only | use native macOS app, or `--platform linux/amd64` (slow) |
| Docker GPU not used | missing NVIDIA Container Toolkit / used CUDA image on AMD | install toolkit; use `--rocm` for AMD |
| macOS "app is damaged / can't be opened" | Gatekeeper quarantine | open via right-click → Open, or see upstream `docs/install/macos.md` |
| Intel Mac backend won't run | unsupported | run backend on another machine (Docker) and point the app to it |
| Old Tauri app installed | archived | back up `omnivoice_data`, follow upstream `docs/electron-migration.md` |

Logs: desktop app → Settings → Logs; Docker → `docker logs -f omnivoice`.
Bug reports go to https://github.com/debpalash/VoiceStudio/issues (the app can prefill one).
