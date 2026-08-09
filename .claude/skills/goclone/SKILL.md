---
name: goclone
description: Download (clone/mirror) a live web page to local disk with the goclone CLI (github.com/goclone-dev/goclone) — grabs the HTML plus its CSS, JS and images and rewrites links so the copy opens offline. Use this skill whenever the user wants to copy, clone, mirror, rip, download, save or "steal the layout of" a website or landing page, wants a local/offline copy of a page to edit or use as a template, or says things like "склонируй сайт", "скачай сайт", "скопируй лендинг", "сделай локальную копию страницы", "clone this URL", "save this page with all assets". Also use it when the user asks to install or set up goclone itself.
---

# goclone — cloning web pages to local disk

`goclone` is a Go CLI that downloads a page and its assets into a folder named
after the domain, then rewrites the links inside the HTML so the copy opens
offline in a browser.

## Install / ensure it is available

Never assume the binary exists — the install script is idempotent and cheap, so
just run it. It prints the binary path on stdout and diagnostics on stderr:

```bash
GOCLONE="$(.claude/skills/goclone/scripts/install.sh)"
```

It tries `go install github.com/goclone-dev/goclone/cmd/goclone@latest`, then
homebrew (`brew tap goclone-dev/goclone && brew install goclone`), then a source
build. Go >= 1.20 is the only real requirement. The binary lands in
`$(go env GOPATH)/bin`, which is often not on `PATH` — that's why the script
returns a full path instead of relying on the command name.

## Cloning

Prefer the wrapper over calling the binary directly. `goclone` writes into the
*current* working directory, which is easy to get wrong, and it exits 0 even
when a page came back empty — the wrapper pins the destination and prints what
actually landed on disk:

```bash
.claude/skills/goclone/scripts/clone.sh -d ./clones https://example.com
```

Options: `-d` output dir (default `.`), `-u` custom User-Agent, `-p` proxy
(http/socks5), `-C` cookies (`"k=v; k2=v2"`), `-n` skip the offline fixup.
Several URLs can be passed at once; each becomes its own folder.

Raw form, if you need a flag the wrapper doesn't expose (note that goclone
writes into the current directory, so `cd` first):

```bash
SKILL_DIR="$PWD/.claude/skills/goclone"
mkdir -p clones && cd clones
"$GOCLONE" --user_agent "Mozilla/5.0 ..." https://example.com
python3 "$SKILL_DIR/scripts/fix_offline.py" example.com
```

Script paths above are written from the repo root; adjust if the working
directory differs.

## The offline fixup (why the wrapper runs it)

goclone keeps cache-busting query strings in asset filenames: it saves
`css/news.css?2HYqx` and writes `href="css/news.css?2HYqx"`. Over `http://`
that resolves; opened from `file://` the browser drops `?2HYqx`, asks for
`css/news.css`, finds nothing, and the page renders unstyled — the classic
"I cloned it but it looks broken" report. `scripts/fix_offline.py` renames those
files, rewrites the references, and lists links that still point at pages this
single-page clone doesn't contain. It is idempotent and supports `--dry-run`.
`clone.sh` runs it automatically; run it yourself after a raw `goclone` call.

## What you get

```
clones/example.com/
├── index.html   # links rewritten to the local files below
├── css/
├── js/
└── imgs/
```

## After cloning, verify — don't just report success

The single most common failure is a clone that "worked" but produced a shell of
a page, so spend a moment checking before telling the user it's done:

- `index.html` under ~1 KB, or with an empty `<body>`, means the site renders
  through JavaScript or refused the request. goclone fetches static HTML only;
  it does not execute JS. Say so plainly and suggest a headless-browser capture
  instead of pretending the clone succeeded.
- Empty `css/`, `js/` or `imgs/` on a visually rich site usually means the
  assets sit behind a CDN that rejected the plain asset fetch, or they use
  extensions goclone doesn't collect (see the limits below).
- A 403/robots-style HTML page saved as `index.html` — retry with a realistic
  `-u` User-Agent, and with `-C` cookies if the page is behind a login.

Reading the saved `index.html` is the fastest way to tell which of these
happened.

## Serving the result

`-s/--serve` (with `-P` for the port, default 5000) starts an Echo server and
blocks until interrupted — run it in the background if you need the shell back,
and don't use `-o/--open` in a headless environment, there is no browser to
open. For a quick look, `python3 -m http.server` inside the folder is usually
simpler.

## Limits worth stating up front

- **One page per URL, not a whole site.** goclone does not follow internal
  links or recurse. To mirror several pages, pass each URL explicitly.
- **Assets collected**: `.css`, `.js`, `.jpg`, `.jpeg`, `.gif`, `.png`, `.svg`
  referenced from `<link rel=stylesheet>`, `<script src>` and `<img src>`.
  Fonts, videos, CSS-referenced background images, `srcset` and inline
  `data:`/`blob:` images are not fetched.
- **Filename collisions**: assets are flattened into one folder per type, so two
  different `main.css` files overwrite each other.
- **In-page navigation stays relative** (`href="about"`), so clicking around the
  offline copy leads nowhere. Clone those URLs too, or rewrite the links to
  absolute ones if the user wants navigation to work.
- `--user_agent`, `--proxy_string` and `--cookie` apply to the HTML pass; asset
  downloads use a plain HTTP client (it does honour `HTTP(S)_PROXY` env vars).

## Legal / ethical note

Cloning someone's page copies their code and content. It's fine for backups,
offline reading, local debugging and studying a layout — mention it briefly if
the user is clearly about to republish someone else's site verbatim, then get on
with the task. Respect robots.txt and the site's terms when it matters.

For flag-by-flag detail, troubleshooting recipes and the output-layout specifics,
read `references/usage.md`.
