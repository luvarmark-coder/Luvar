#!/usr/bin/env python3
"""Post-process a goclone project so it actually opens from file://.

goclone keeps cache-busting query strings in asset filenames: it saves
``css/news.css?2HYqx`` on disk and writes ``href="css/news.css?2HYqx"`` into the
HTML. Over http:// that resolves; over file:// the browser strips ``?2HYqx``,
asks for ``css/news.css``, and the page renders unstyled. This script renames
those files and rewrites the references to match.

It also reports links that still point at the live site, since goclone clones a
single page and leaves in-site navigation dangling.

Usage:
    fix_offline.py <project_dir> [--dry-run]

Idempotent: running it twice changes nothing the second time.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ASSET_DIRS = ("css", "js", "imgs")


def strip_queries(project: Path, dry_run: bool) -> list[tuple[str, str]]:
    """Rename ``name.ext?query`` -> ``name.ext``; return (old, new) rel paths."""
    renames: list[tuple[str, str]] = []
    for sub in ASSET_DIRS:
        d = project / sub
        if not d.is_dir():
            continue
        for f in sorted(d.iterdir()):
            if not f.is_file() or "?" not in f.name:
                continue
            clean = f.name.split("?", 1)[0]
            if not clean:
                continue
            target = d / clean
            # Don't clobber a distinct file that already owns the clean name.
            if target.exists() and target.stat().st_size != f.stat().st_size:
                print(f"  skip {f.name}: {clean} already exists with other content",
                      file=sys.stderr)
                continue
            renames.append((f"{sub}/{f.name}", f"{sub}/{clean}"))
            if not dry_run:
                f.replace(target)
    return renames


def rewrite_html(html_path: Path, renames: list[tuple[str, str]], dry_run: bool) -> int:
    text = html_path.read_text(encoding="utf-8", errors="replace")
    original = text
    for old, new in renames:
        text = text.replace(old, new)
    # Catch references goclone wrote that have no file counterpart left.
    text = re.sub(r'((?:href|src)="(?:css|js|imgs)/[^"?]+)\?[^"]*"', r'\1"', text)
    if text != original and not dry_run:
        html_path.write_text(text, encoding="utf-8")
    return sum(1 for a, b in zip(original.split("\n"), text.split("\n")) if a != b)


def report_dangling(html_path: Path) -> list[str]:
    """Relative hrefs that point at pages this single-page clone doesn't have."""
    text = html_path.read_text(encoding="utf-8", errors="replace")
    out = []
    for href in re.findall(r'href="([^"]+)"', text):
        if href.startswith(("http://", "https://", "#", "mailto:", "data:", "//")):
            continue
        if href.split("?")[0].split("/")[0] in ASSET_DIRS:
            continue
        out.append(href)
    return sorted(set(out))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project", type=Path, help="goclone project dir (the one with index.html)")
    ap.add_argument("--dry-run", action="store_true", help="report without changing files")
    args = ap.parse_args()

    project: Path = args.project
    index = project / "index.html"
    if not index.is_file():
        print(f"error: {index} not found — is that a goclone project dir?", file=sys.stderr)
        return 1

    renames = strip_queries(project, args.dry_run)
    verb = "would rename" if args.dry_run else "renamed"
    for old, new in renames:
        print(f"  {verb} {old} -> {new}")

    changed = rewrite_html(index, renames, args.dry_run)
    print(f"{'would rewrite' if args.dry_run else 'rewrote'} {changed} line(s) in index.html")

    dangling = report_dangling(index)
    if dangling:
        preview = ", ".join(dangling[:8])
        more = f" (+{len(dangling) - 8} more)" if len(dangling) > 8 else ""
        print(f"note: {len(dangling)} relative link(s) point at pages not in this clone: "
              f"{preview}{more}")

    if not renames and not changed:
        print("nothing to fix — assets already resolve offline")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
