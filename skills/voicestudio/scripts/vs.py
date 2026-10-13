#!/usr/bin/env python3
"""VoiceStudio command-line client (standard library only).

Talks to a running VoiceStudio backend (default http://localhost:3900).

Environment:
  VOICESTUDIO_URL     backend base URL (default http://localhost:3900)
  OMNIVOICE_API_KEY   bearer key for protected / remote deployments
  OMNIVOICE_PIN       LAN share PIN (sent as X-OmniVoice-Pin)

Examples:
  vs.py health
  vs.py doctor
  vs.py voices
  vs.py models
  vs.py install-model k2-fsa/OmniVoice --yes
  vs.py speak "Hello there" -o hello.wav --voice "My voice" --language en
  vs.py clone "My voice" --audio me.wav --ref-text "what I said" --i-own-this-voice
  vs.py design "Narrator" --description "deep calm male narrator, British accent"
  vs.py transcribe clip.mp3 --format srt -o clip.srt
  vs.py dub movie.mp4 --source-lang en
  vs.py mcp-config claude-code
"""
from __future__ import annotations

import argparse
import http.client
import json
import mimetypes
import os
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import wave

BASE = os.environ.get("VOICESTUDIO_URL", "http://localhost:3900").rstrip("/")
TIMEOUT = float(os.environ.get("VOICESTUDIO_TIMEOUT", "1900"))


class ApiError(Exception):
    def __init__(self, status: int, body: str, url: str):
        super().__init__(f"HTTP {status} from {url}: {body[:800]}")
        self.status = status
        self.body = body


# ── HTTP helpers ──────────────────────────────────────────────────────────

def _headers(extra: dict | None = None) -> dict:
    h = {"Accept": "application/json, audio/*, */*"}
    key = os.environ.get("OMNIVOICE_API_KEY")
    pin = os.environ.get("OMNIVOICE_PIN")
    if key:
        h["Authorization"] = f"Bearer {key}"
    if pin:
        h["X-OmniVoice-Pin"] = pin
    if extra:
        h.update(extra)
    return h


def request(method: str, path: str, *, data: bytes | None = None,
            headers: dict | None = None, timeout: float = TIMEOUT):
    url = path if path.startswith("http") else BASE + path
    req = urllib.request.Request(url, data=data, method=method, headers=_headers(headers))
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as e:
        raise ApiError(e.code, e.read().decode("utf-8", "replace"), url) from None
    except urllib.error.URLError as e:
        raise SystemExit(
            f"Cannot reach VoiceStudio at {BASE} ({e.reason}).\n"
            "Start the VoiceStudio app (or Docker container) and retry, or set VOICESTUDIO_URL."
        )
    except (OSError, http.client.HTTPException) as e:
        raise SystemExit(f"Connection to {url} failed: {e!r}. The backend may have restarted or "
                         "timed out; check `vs.py health` and the app logs before retrying.")


def get_json(path: str, timeout: float = 30):
    _, _, body = request("GET", path, timeout=timeout)
    return json.loads(body or b"null")


def post_json(path: str, payload: dict, timeout: float = TIMEOUT):
    return request("POST", path, data=json.dumps(payload).encode(),
                   headers={"Content-Type": "application/json"}, timeout=timeout)


def post_multipart(path: str, fields: dict, files: dict, timeout: float = TIMEOUT):
    boundary = "----vs" + uuid.uuid4().hex
    parts: list[bytes] = []
    for k, v in fields.items():
        if v is None:
            continue
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    for k, fpath in files.items():
        if not fpath:
            continue
        name = os.path.basename(fpath)
        ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
        with open(fpath, "rb") as fh:
            content = fh.read()
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"; filename="{name}"\r\n'
            f"Content-Type: {ctype}\r\n\r\n".encode() + content + b"\r\n"
        )
    parts.append(f"--{boundary}--\r\n".encode())
    return request("POST", path, data=b"".join(parts),
                   headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
                   timeout=timeout)


def pretty(obj) -> None:
    print(json.dumps(obj, ensure_ascii=False, indent=2))


def _list(obj, *keys):
    """Return the first list found in obj (a list itself or under one of keys)."""
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        for k in keys:
            if isinstance(obj.get(k), list):
                return obj[k]
    return []


def describe_audio(path: str) -> str:
    size = os.path.getsize(path)
    info = f"{path} ({size:,} bytes"
    try:
        with wave.open(path, "rb") as w:
            dur = w.getnframes() / float(w.getframerate())
            info += f", {dur:.2f} s, {w.getframerate()} Hz, {w.getnchannels()} ch WAV"
    except Exception:
        if shutil.which("ffprobe"):
            import subprocess
            r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                "-of", "default=nw=1:nk=1", path], capture_output=True, text=True)
            if r.stdout.strip():
                info += f", {float(r.stdout.strip()):.2f} s"
    return info + ")"


# ── Commands ──────────────────────────────────────────────────────────────

def cmd_health(_a):
    try:
        status, _, body = request("GET", "/health", timeout=10)
        pretty(json.loads(body))
    except ApiError as e:
        if e.status == 503:
            print("Backend is starting:", e.body)
            sys.exit(2)
        raise


def cmd_doctor(_a):
    ok = True
    print(f"Backend URL: {BASE}")
    try:
        h = get_json("/health", timeout=10)
        print(f"[ok]  health: status={h.get('status')} device={h.get('device')} version={h.get('version')}")
    except ApiError as e:
        print(f"[!!]  health: {e}")
        sys.exit(1)
    try:
        models = _list(get_json("/models"), "models", "items")
        inst = [m.get("repo_id") for m in models if m.get("installed")]
        print(f"[{'ok' if inst else '!!'}]  models installed: {', '.join(inst) or 'none'}")
        ok &= bool(inst)
    except ApiError as e:
        print(f"[??]  models: {e}")
    try:
        voices = _list(get_json("/v1/audio/voices"), "voices", "data")
        print(f"[ok]  voices available: {len(voices)}")
    except ApiError as e:
        print(f"[??]  voices: {e}")
    try:
        _, _, body = request("GET", "/openapi.json", timeout=20)
        n = len(json.loads(body).get("paths", {}))
        print(f"[ok]  openapi: {n} paths")
    except ApiError as e:
        print(f"[??]  openapi: {e}")
    print("[ok]  ffmpeg on this machine" if shutil.which("ffmpeg")
          else "[--]  ffmpeg not on PATH here (the app downloads its own copy)")
    if not ok:
        print("\nNo model installed: run `vs.py models`, pick one, ask the user, then `vs.py install-model <repo_id> --yes`.")
    sys.exit(0 if ok else 1)


def cmd_voices(a):
    data = get_json("/v1/audio/voices")
    if a.json:
        return pretty(data)
    voices = _list(data, "voices", "data")
    if not voices:
        return pretty(data)
    for v in voices:
        if isinstance(v, dict):
            print(f"{v.get('voice_id', ''):40} {v.get('name', ''):30} {v.get('type', ''):14} {v.get('language') or ''}")
        else:
            print(v)


def cmd_profiles(a):
    pretty(get_json("/profiles"))


def cmd_models(a):
    data = get_json("/models")
    if a.json:
        return pretty(data)
    models = _list(data, "models", "items")
    for m in models:
        mark = "installed " if m.get("installed") else "-         "
        size = m.get("size_gb") or m.get("size") or ""
        print(f"{mark} {m.get('repo_id', ''):45} {str(size):>8}  {m.get('label', '') or m.get('name', '')}")


def cmd_install_model(a):
    if not a.yes:
        raise SystemExit("Model downloads need the user's consent. Tell them the size and license "
                         "(see `vs.py models --json`), then re-run with --yes.")
    try:
        _, _, body = post_json("/models/install", {"repo_id": a.repo_id})
        print("install started:", body.decode("utf-8", "replace")[:300])
    except ApiError as e:
        if e.status in (409,):
            print("already installing:", e.body[:300])
        else:
            raise
    while True:
        time.sleep(5)
        st = get_json("/models/install/status")
        jobs = _list(st, "jobs")
        mine = [j for j in jobs if j.get("repo_id") == a.repo_id]
        if any(j.get("state") == "failed" for j in mine):
            pretty(mine)
            raise SystemExit("install failed")
        if mine:
            j = mine[0]
            pct = j.get("percent") or j.get("progress") or ""
            print(f"  {j.get('state')} {pct}", flush=True)
            continue
        models = _list(get_json("/models"), "models", "items")
        m = next((m for m in models if m.get("repo_id") == a.repo_id), None)
        if m and m.get("installed"):
            print(f"{a.repo_id} installed.")
            return
        print("  waiting for model to register…", flush=True)


def cmd_speak(a):
    text = a.text
    if a.text_file:
        with open(a.text_file, encoding="utf-8") as fh:
            text = fh.read()
    if not text:
        raise SystemExit("Provide text or --text-file")
    payload = {"model": a.model, "input": text, "response_format": a.format,
               "voice": a.voice or "alloy", "speed": a.speed}
    for k in ("language", "instructions", "seed"):
        v = getattr(a, k)
        if v is not None:
            payload[k] = v
    out = a.output or f"speech.{a.format}"
    t0 = time.time()
    if len(text) > 4000:
        # OpenAI-compatible route caps input at 4096 chars; use native /generate.
        fields = {"text": text, "language": a.language, "instruct": a.instructions,
                  "speed": a.speed, "seed": a.seed}
        if a.voice:
            fields["profile_id"] = _resolve_profile_id(a.voice)
        _, headers, body = post_multipart("/generate", fields, {})
    else:
        _, headers, body = post_json("/v1/audio/speech", payload)
    ctype = headers.get("Content-Type", headers.get("content-type", ""))
    if "json" in ctype:
        raise SystemExit(f"Expected audio, got JSON: {body[:500].decode('utf-8', 'replace')}")
    with open(out, "wb") as fh:
        fh.write(body)
    print(f"saved {describe_audio(out)} in {time.time() - t0:.1f}s")


def _resolve_profile_id(voice: str) -> str:
    try:
        profiles = _list(get_json("/profiles"), "profiles", "items")
    except ApiError:
        return voice
    for p in profiles:
        if voice in (p.get("id"), p.get("name")):
            return p.get("id")
    return voice


def cmd_clone(a):
    if not a.i_own_this_voice:
        raise SystemExit("Cloning requires confirming the user owns this voice or has the speaker's "
                         "consent. Re-run with --i-own-this-voice once confirmed.")
    fields = {"name": a.name, "ref_text": a.ref_text or "", "language": a.language,
              "kind": "clone", "instruct": a.instruct or ""}
    _, _, body = post_multipart("/profiles", fields, {"ref_audio": a.audio})
    pretty(json.loads(body))


def cmd_design(a):
    # Same flow as the MCP design_voice tool: map the description, then save.
    _, _, body = post_json("/design/describe", {"description": a.description}, timeout=60)
    parsed = json.loads(body)
    if not parsed.get("matched"):
        raise SystemExit("The description matched no design attribute (unmatched: "
                         f"{parsed.get('unmatched')}). Use words for gender, age, pitch, style, accent.")
    print("mapped:", parsed.get("instruct"), "| unmatched:", parsed.get("unmatched") or "-")
    fields = {"name": a.name, "kind": "design", "vd_states": json.dumps(parsed["attrs"]),
              "instruct": parsed.get("instruct", ""), "language": a.language}
    _, _, body = post_multipart("/profiles", fields, {})
    pretty(json.loads(body))


def cmd_transcribe(a):
    path = "/v1/audio/translations" if a.translate else "/v1/audio/transcriptions"
    fields = {"model": "whisper-1", "response_format": a.format, "language": a.language}
    _, _, body = post_multipart(path, fields, {"file": a.file})
    text = body.decode("utf-8", "replace")
    if a.output:
        with open(a.output, "w", encoding="utf-8") as fh:
            fh.write(text)
        print(f"saved {a.output}")
    else:
        print(text)


def cmd_dub(a):
    input_type = "audio" if (mimetypes.guess_type(a.file)[0] or "").startswith("audio") else "video"
    _, _, body = post_multipart("/dub/upload", {"input_type": input_type, "source_lang": a.source_lang},
                                {"video": a.file})
    info = json.loads(body)
    pretty(info)
    print("\nUploaded. Continue in the app's Dubbing workspace, or drive the stages via "
          "/dub/transcribe/{job_id}, /dub/translate, /dub/generate/{job_id}, /dub/download/{job_id}. "
          "Check /openapi.json for their request bodies.")


def cmd_jobs(a):
    pretty(get_json(f"/jobs/{a.job_id}" if a.job_id else "/jobs"))


def cmd_openapi(a):
    spec = get_json("/openapi.json")
    for p, ops in sorted(spec.get("paths", {}).items()):
        if a.filter and a.filter not in p:
            continue
        print(f"{','.join(m.upper() for m in ops):18} {p}")


def cmd_mcp_config(a):
    host = BASE.replace("localhost", "127.0.0.1")
    url = f"{host}/mcp/"
    cid = a.client
    if cid == "codex":
        print(f'[mcp_servers.voicestudio]\nurl = "{url}"\nhttp_headers = {{ "X-OmniVoice-Client-Id" = "codex-cli" }}')
    elif cid == "cursor":
        pretty({"mcpServers": {"voicestudio": {"url": url, "headers": {"X-OmniVoice-Client-Id": "cursor"}}}})
    else:
        pretty({"mcpServers": {"voicestudio": {"type": "http", "url": url,
                                                "headers": {"X-OmniVoice-Client-Id": "claude-code"}}}})
        print(f'\n# or: claude mcp add --transport http voicestudio {url} '
              f'--header "X-OmniVoice-Client-Id: claude-code"')


def cmd_bind(a):
    profile_id = _resolve_profile_id(a.voice)
    _, _, body = request("PUT", "/api/mcp/bindings",
                         data=json.dumps({"client_id": a.client_id, "label": a.client_id,
                                          "profile_id": profile_id}).encode(),
                         headers={"Content-Type": "application/json"})
    print(body.decode("utf-8", "replace"))


def main():
    p = argparse.ArgumentParser(description="VoiceStudio CLI", formatter_class=argparse.RawDescriptionHelpFormatter,
                                epilog=__doc__.split("Examples:")[1])
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("health", help="backend status and device").set_defaults(fn=cmd_health)
    sub.add_parser("doctor", help="full readiness check").set_defaults(fn=cmd_doctor)
    s = sub.add_parser("voices", help="list voices usable for speech"); s.add_argument("--json", action="store_true"); s.set_defaults(fn=cmd_voices)
    sub.add_parser("profiles", help="raw voice profiles").set_defaults(fn=cmd_profiles)
    s = sub.add_parser("models", help="list engines/models"); s.add_argument("--json", action="store_true"); s.set_defaults(fn=cmd_models)
    s = sub.add_parser("install-model", help="download a model (needs consent)")
    s.add_argument("repo_id"); s.add_argument("--yes", action="store_true"); s.set_defaults(fn=cmd_install_model)

    s = sub.add_parser("speak", help="text to speech")
    s.add_argument("text", nargs="?"); s.add_argument("--text-file"); s.add_argument("-o", "--output")
    s.add_argument("--voice"); s.add_argument("--language"); s.add_argument("--instructions")
    s.add_argument("--speed", type=float, default=1.0); s.add_argument("--seed", type=int)
    s.add_argument("--format", default="wav", choices=["wav", "mp3", "opus", "flac", "aac", "pcm"])
    s.add_argument("--model", default="tts-1"); s.set_defaults(fn=cmd_speak)

    s = sub.add_parser("clone", help="clone a voice from a reference recording")
    s.add_argument("name"); s.add_argument("--audio", required=True); s.add_argument("--ref-text")
    s.add_argument("--language", default="Auto"); s.add_argument("--instruct")
    s.add_argument("--i-own-this-voice", action="store_true"); s.set_defaults(fn=cmd_clone)

    s = sub.add_parser("design", help="design a voice from a description")
    s.add_argument("name"); s.add_argument("--description", required=True)
    s.add_argument("--language", default="Auto"); s.set_defaults(fn=cmd_design)

    s = sub.add_parser("transcribe", help="speech to text / subtitles")
    s.add_argument("file"); s.add_argument("-o", "--output"); s.add_argument("--language")
    s.add_argument("--format", default="text", choices=["text", "json", "verbose_json", "srt", "vtt"])
    s.add_argument("--translate", action="store_true", help="translate to English"); s.set_defaults(fn=cmd_transcribe)

    s = sub.add_parser("dub", help="upload media to start a dubbing job")
    s.add_argument("file"); s.add_argument("--source-lang"); s.set_defaults(fn=cmd_dub)

    s = sub.add_parser("jobs", help="list jobs or show one"); s.add_argument("job_id", nargs="?"); s.set_defaults(fn=cmd_jobs)
    s = sub.add_parser("openapi", help="list API paths of the running version"); s.add_argument("filter", nargs="?"); s.set_defaults(fn=cmd_openapi)
    s = sub.add_parser("mcp-config", help="print MCP client config")
    s.add_argument("client", nargs="?", default="claude-code", choices=["claude-code", "cursor", "codex"]); s.set_defaults(fn=cmd_mcp_config)
    s = sub.add_parser("bind", help="bind an MCP client id to a voice")
    s.add_argument("client_id"); s.add_argument("voice"); s.set_defaults(fn=cmd_bind)

    a = p.parse_args()
    try:
        a.fn(a)
    except ApiError as e:
        print(e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
