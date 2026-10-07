---
name: markitdown
description: Convert a document, spreadsheet, presentation, web page, or archive into plain Markdown text using Microsoft's markitdown CLI. Use when the goal is to READ or EXTRACT text/tables out of a PDF, DOCX, XLSX, PPTX, HTML, CSV, JSON, EPUB, ZIP, image, or a URL so the content can be summarized, searched, quoted, or piped into another step. Also use to repair a session where the `markitdown` command is missing or was never installed. Do NOT use when the deliverable is itself a .docx/.xlsx/.pptx/.pdf file — the dedicated docx/xlsx/pptx/pdf skills own creating and editing those.
---

# markitdown

One command turns almost any file into Markdown on stdout. Prefer it over
hand-rolled parsing (`pdfplumber`, `python-docx`, BeautifulSoup) when all you
need is the text.

## 1. Make sure it is installed

The SessionStart hook (`.claude/hooks/session-start.sh`) normally installs this
before the session begins. If `markitdown` is not on PATH — the hook was
skipped, the settings file was not trusted, or this is a fresh container — run
the hook by hand; it is idempotent:

```bash
export PATH="$HOME/.local/bin:$PATH"
command -v markitdown || bash "$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh"
```

Standalone fallback if the hook file is unavailable:

```bash
uv tool install 'markitdown[all]'   # or: pipx install 'markitdown[all]'
```

Always `export PATH="$HOME/.local/bin:$PATH"` first in a fresh shell — the
binary lands there and is not on the default PATH.

## 2. Convert

```bash
markitdown report.pdf                  # -> stdout
markitdown deck.pptx -o deck.md        # -> file
markitdown https://example.com         # fetches the URL
cat page.html | markitdown -x html     # stdin REQUIRES -x/--extension
```

Without `-x`, stdin input is treated as plain text and passes through
unchanged — a silent no-op, not an error. This is the most common mistake.

## 3. What comes out

| Input | Output |
|---|---|
| PDF | text, reading order; no OCR for scanned pages |
| DOCX / PPTX / XLSX | headings, lists, tables as Markdown pipe tables; PPTX adds `<!-- Slide number: N -->` |
| HTML / URL | headings, `**bold**`, links, tables |
| CSV / JSON / XML | structured text |
| ZIP | iterates members and converts each |
| YouTube URL | video metadata plus transcript |
| Images | EXIF metadata only, unless an LLM client is configured |
| Audio | EXIF plus speech transcription |

## 4. Known limits — check before promising a result

- **Scanned PDFs yield nothing.** No OCR is built in. If output is empty or
  near-empty, say so rather than reporting a successful conversion.
- **Audio needs `ffmpeg`** on PATH, and transcription calls an online speech
  API. On unrecognizable audio markitdown raises `FileConversionException`
  (`UnknownValueError`) instead of falling back to metadata — catch it.
- **Images return metadata, not a description**, unless `--llm-client` is set.
- Complex multi-column PDF layouts can interleave columns; spot-check before
  quoting figures from one.

## 5. In Python

```python
from markitdown import MarkItDown
print(MarkItDown().convert("report.pdf").text_content)
```

Use the tool's own interpreter, since the CLI is installed into an isolated
environment and its libraries are not importable from the system Python:

```bash
/root/.local/share/uv/tools/markitdown/bin/python script.py
```
