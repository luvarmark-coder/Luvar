# goclone reference

Upstream: <https://github.com/goclone-dev/goclone> (MIT). Verified against
`v1.2.2`, the version `go install ...@latest` currently resolves to.

## Contents

- [Installation details](#installation-details)
- [CLI flags](#cli-flags)
- [How it actually works](#how-it-actually-works)
- [Output layout](#output-layout)
- [Troubleshooting](#troubleshooting)
- [Alternatives when goclone is the wrong tool](#alternatives-when-goclone-is-the-wrong-tool)

## Installation details

```bash
go install github.com/goclone-dev/goclone/cmd/goclone@latest   # any platform, Go >= 1.20
brew tap goclone-dev/goclone && brew install goclone           # macOS/Linux with brew
```

Source build:

```bash
git clone https://github.com/goclone-dev/goclone.git
cd goclone && go build -o goclone ./cmd/goclone
```

Notes:

- The binary goes to `$(go env GOBIN)`, falling back to `$(go env GOPATH)/bin`
  (usually `~/go/bin`). Add it to `PATH` or call it by full path.
- The `master` branch declares a newer Go version in `go.mod` than the tagged
  releases do. With `GOTOOLCHAIN=auto` (the default) Go downloads the matching
  toolchain automatically; in a locked-down environment build a tag instead:
  `go install github.com/goclone-dev/goclone/cmd/goclone@v1.2.2`.
- Tagged releases have no `version` subcommand — `goclone version` errors with
  `"version" is not valid`. Use `goclone --help` to confirm the binary runs.

## CLI flags

```
Usage:
  goclone <url> [url...] [flags]

  -C, --cookie strings        Pre-set these cookies, e.g. -C "session=abc; theme=dark"
  -o, --open                  Open the result in the default browser
  -p, --proxy_string string   Proxy connection string (http and socks5)
  -s, --serve                 Serve the generated files (Echo static server)
  -P, --servePort int         Serve port (default 5000)
  -u, --user_agent string     Custom User-Agent
  -h, --help                  Help
```

Behavioural details:

- With no arguments it prints usage and exits 0.
- Multiple URLs clone sequentially into separate folders; cookies are set for
  every host given.
- `--serve` blocks until Ctrl-C (SIGINT). Combined with `--open` it opens
  `http://localhost:<port>`; alone, `--open` opens the local `index.html`.
- `--open` shells out to `xdg-open`/`open`/`start` — useless and noisy on a
  headless box.
- A bare domain works (`goclone example.com`); it is expanded to `https://`.

## How it actually works

1. Fetch the page HTML and write it to `<domain>/index.html`.
2. Re-parse with colly, and for every `link[rel=stylesheet]`, `script[src]` and
   `img[src]`, download the target with a plain `http.Get`.
3. Sort each downloaded file into `css/`, `js/` or `imgs/` by extension —
   anything else is silently discarded.
4. Rewrite the asset references in `index.html` to the local paths and reformat
   the HTML.

Consequences: no JavaScript execution, no link following, no `srcset`/CSS
`url()` resolution, and asset downloads bypass the `--user_agent` / `--cookie`
/ `--proxy_string` settings (they do respect `HTTP_PROXY` / `HTTPS_PROXY`
environment variables).

The saved filename is the last URL path segment *including any query string*,
so `news.css?2HYqxKC9` lands on disk under that exact name and is referenced
that way in the HTML. Served over http:// it works; opened via `file://` the
browser strips the query and the asset 404s. `scripts/fix_offline.py` undoes
this — `clone.sh` runs it for you.

## Output layout

```
<cwd>/<domain>/
├── index.html
├── css/
├── js/
└── imgs/
```

The folder is named after the host only (`example.com`), so cloning
`example.com/a` and `example.com/b` into the same directory makes the second
clone overwrite the first. Give each one its own `-d` directory, or rename
between runs.

Directories are created with mode 0777 and are created even when empty, so
"the css folder exists" is not evidence that any CSS downloaded — count the
files.

## Troubleshooting

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| `index.html` tiny or body empty | SPA / JS-rendered page | goclone can't help; capture with a headless browser (Playwright `page.content()`) instead |
| Saved page is a 403 / captcha / "enable JS" notice | Bot protection | Retry with a realistic `-u` User-Agent; add `-C` cookies from a logged-in session |
| Page fine, assets missing | CDN rejected the plain asset request, or unsupported extension (fonts, `.webp`, `.avif`, `.mp4`, CSS `url()` images) | Download the few needed files manually with curl |
| Page opens unstyled from `file://`, but the CSS file is clearly there | Asset saved as `news.css?2HYqx` and referenced with the query string; `file://` strips it | `scripts/fix_offline.py <project_dir>` (already automatic in `clone.sh`) |
| Clicking a link in the copy goes nowhere | Single-page clone; in-site links stay relative | Clone those URLs too, or make the links absolute |
| `command not found: goclone` | `$(go env GOPATH)/bin` not on `PATH` | Call the binary by full path (what `scripts/install.sh` returns) |
| `"version" is not valid` | No `version` subcommand in tagged releases | Use `--help` |
| Hangs after cloning | `--serve` is running its server | Expected; Ctrl-C, or run in the background |
| `%q is not valid` | Malformed URL argument | Pass a full `https://…` URL |
| Two assets with the same basename | Flat per-type folders | Rename in `index.html` and on disk, or fetch the clashing file manually |

## Alternatives when goclone is the wrong tool

- **Whole-site recursive mirror**: `wget --mirror --convert-links --page-requisites --adjust-extension <url>`, or `httrack`.
- **JS-rendered pages**: Playwright/Puppeteer — render, then save `page.content()` and the network responses.
- **Just the readable text**: `curl` + an HTML-to-text pass, or the WebFetch tool.
