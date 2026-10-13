---
name: whisper
description: Transcribe or translate speech from audio/video files with OpenAI Whisper (speech-to-text, subtitles, language detection). Use when the user asks to transcribe audio, make subtitles (srt/vtt), translate speech to English, or detect the spoken language of a recording.
---

# Whisper (openai/whisper)

Speech recognition model: multilingual transcription, speech-to-English translation, language identification.
Source: https://github.com/openai/whisper

## Setup (once)

```bash
pip install -U openai-whisper          # or: pip install git+https://github.com/openai/whisper.git
# ffmpeg is required
sudo apt update && sudo apt install -y ffmpeg      # macOS: brew install ffmpeg
```

If `tiktoken` fails to build, install Rust (`https://rustup.rs`) and `pip install setuptools-rust`.
Check first with `which whisper ffmpeg` before installing.

## Models

| Model | Params | VRAM | Notes |
|---|---|---|---|
| tiny / tiny.en | 39M | ~1 GB | fastest, lowest accuracy |
| base / base.en | 74M | ~1 GB | |
| small / small.en | 244M | ~2 GB | good CPU choice |
| medium / medium.en | 769M | ~5 GB | |
| large | 1550M | ~10 GB | best accuracy, slowest |
| turbo | 809M | ~6 GB | default; fast large-v3 variant, **not for translation** |

`.en` models are English-only and slightly better for English. On CPU-only machines prefer `small`/`base`.

## CLI usage

```bash
# Transcribe (language auto-detected), all output formats
whisper audio.mp3 --model turbo

# Specific language and output format/location
whisper audio.wav --language Russian --model small --output_format srt --output_dir ./out

# Translate non-English speech to English (use medium/large, NOT turbo)
whisper speech.wav --model medium --task translate

# Word-level timestamps / subtitle formatting
whisper audio.mp3 --word_timestamps True --max_line_width 42 --max_line_count 2 --output_format srt
```

Useful options: `--output_format {txt,vtt,srt,tsv,json,jsonl,all}`, `--output_dir`, `--device {cpu,cuda}`,
`--fp16 False` (required on CPU to silence the fp16 warning), `--initial_prompt "names/terms"` (improves
spelling of jargon), `--condition_on_previous_text False` (fixes repetition loops), `--threads N`,
`--clip_timestamps start,end`. Run `whisper --help` for the full list.

Video files (mp4, mkv, …) work directly since ffmpeg decodes them.

## Python usage

```python
import whisper
model = whisper.load_model("turbo")
result = model.transcribe("audio.mp3", language=None)   # result["text"], result["segments"], result["language"]
print(result["text"])
```

Language detection only:

```python
audio = whisper.pad_or_trim(whisper.load_audio("audio.mp3"))
mel = whisper.log_mel_spectrogram(audio, n_mels=model.dims.n_mels).to(model.device)
_, probs = model.detect_language(mel)
print(max(probs, key=probs.get))
```

## Workflow

1. Confirm the input file exists and `whisper`/`ffmpeg` are installed (install if missing).
2. Pick a model by hardware and goal (see table); use `--task translate` only with non-turbo multilingual models.
3. Run the CLI, writing outputs to a dedicated `--output_dir`.
4. Report the detected language and show/summarize the transcript, giving the output file paths.

## Pitfalls

- First run downloads model weights to `~/.cache/whisper` (needs network access).
- Long hallucinated/repeated text in silence: use `--condition_on_previous_text False` and/or `--hallucination_silence_threshold 2` with `--word_timestamps True`.
- `turbo` returns the original language even with `--task translate`.
- Whisper does not do speaker diarization.
