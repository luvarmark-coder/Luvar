# VoiceStudio over MCP

The backend mounts an MCP server at `http://localhost:3900/mcp/` (keep the trailing
slash for older versions). Nothing extra to start — VoiceStudio must just be running.

## Connect

Claude Code:

```sh
claude mcp add --transport http voicestudio http://127.0.0.1:3900/mcp/ \
  --header "X-OmniVoice-Client-Id: claude-code"
```

or `.mcp.json` in the project (`python3 scripts/vs.py mcp-config claude-code`):

```json
{"mcpServers":{"voicestudio":{"type":"http","url":"http://127.0.0.1:3900/mcp/",
  "headers":{"X-OmniVoice-Client-Id":"claude-code"}}}}
```

Cursor (`.cursor/mcp.json`): `vs.py mcp-config cursor`. Codex (`~/.codex/config.toml`):

```toml
[mcp_servers.voicestudio]
url = "http://127.0.0.1:3900/mcp/"
http_headers = { "X-OmniVoice-Client-Id" = "codex-cli" }
```

stdio-only clients need a source checkout and the shim:
`{"command":"python","args":["-m","backend.mcp_shim"],"cwd":"/path/to/VoiceStudio","env":{"OMNIVOICE_PORT":"3900","OMNIVOICE_CLIENT_ID":"claude-code"}}`

## Tools

| Tool | Does |
|---|---|
| `generate_speech` | text → WAV (or ogg/opus in files mode); uses bound voice unless `profile_id` given |
| `clone_voice` | reference audio (base64 or `ref_audio_path` under base path) → `profile_id` |
| `describe_voice` | description → design attributes (saves nothing) |
| `design_voice` | description → new design voice `profile_id` |
| `transcribe` | audio → text (646 languages) |
| `list_voices`, `list_personalities`, `list_languages` | discovery |
| `check_health` | status + device |

Resources: `voice://{profile_id}`, `history://recent` (JSON text).

## Keep audio out of the chat context

Set on the backend's environment:

| Variable | Meaning |
|---|---|
| `OMNIVOICE_MCP_OUTPUT_MODE=files` | return `audio_url` + `output_path` instead of base64 (`resources` default, `both`) |
| `OMNIVOICE_MCP_BASE_PATH=/dir` | the only directory MCP may read inputs from / write files into |
| `OMNIVOICE_MCP_TIMEOUT_S` | fixed tool timeout (default follows backend) |
| `OMNIVOICE_MCP_ALLOWED_HOSTS` | extra Host patterns (Docker, hostnames), e.g. `host.docker.internal:*` |
| `OMNIVOICE_MCP_DISABLE=1` | don't mount `/mcp` |

## Per-agent voices

Precedence: explicit `profile_id` → agent's binding → default voice.

```sh
python3 scripts/vs.py bind claude-code "My voice"      # or:
curl -X PUT localhost:3900/api/mcp/bindings -H 'Content-Type: application/json' \
  -d '{"client_id":"claude-code","label":"Claude Code","profile_id":"<id>"}'
curl localhost:3900/api/mcp/bindings                    # list
curl -X DELETE localhost:3900/api/mcp/bindings/claude-code
```

## Other machines

Settings → Sharing → Local network gives a LAN address + 6-digit PIN; send it as
`X-OmniVoice-Pin`. HTTP on a LAN is unencrypted — on untrusted networks use Tailscale
Serve / HTTPS reverse proxy with its own auth. Never expose `/mcp` to the internet.
