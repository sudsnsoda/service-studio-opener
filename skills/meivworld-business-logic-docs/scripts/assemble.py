#!/usr/bin/env python3
"""Assemble a Meivworld Business Logic page into one self-contained HTML file.

Usage:
  python scripts/assemble.py --title "X Business Logic" --body body.html \
      [--refdata refdata.json] --out out/index.html [--favicon "📘"]

body.html holds the <div class="wrap"> ... </div> (nav + main, ending with the
reference section when --refdata is used). CSS and both scripts are inlined from
assets/. refdata.json is {"Module": [[kind, name, pseudo-code], ...], ...}.
"""
import argparse, html, json, pathlib, sys

ASSETS = pathlib.Path(__file__).resolve().parent.parent / "assets"

def read(name):
    return (ASSETS / name).read_text(encoding="utf-8")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--title", required=True)
    ap.add_argument("--body", required=True)
    ap.add_argument("--refdata")
    ap.add_argument("--out", required=True)
    ap.add_argument("--favicon", default="📘")
    a = ap.parse_args()

    body = pathlib.Path(a.body).read_text(encoding="utf-8")
    if 'class="wrap"' not in body:
        sys.exit('body.html must contain <div class="wrap"> ... </div> (nav + main)')
    if a.refdata and 'id="reflist"' not in body:
        sys.exit("--refdata given but body.html has no reference section (assets/reference-section.html)")
    if 'id="reflist"' in body and not a.refdata:
        sys.exit("body.html has the reference section but --refdata was not given")

    parts = [
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">",
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">",
        f"<title>{html.escape(a.title)}</title>",
        f"<link rel=\"icon\" href=\"data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>{a.favicon}</text></svg>\">",
        "<link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">",
        "<link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>",
        "<link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=Archivo:wght@500;600;700;800&family=Source+Sans+3:ital,wght@0,400;0,600;0,700;1,400&family=JetBrains+Mono:wght@400;600&display=swap\">",
        "<style>", read("page-style.css"), "</style></head><body>",
        body,
    ]
    if a.refdata:
        try:
            data = json.loads(pathlib.Path(a.refdata).read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            sys.exit(f"refdata.json is not valid JSON: {e}")
        if not isinstance(data, dict):
            sys.exit("refdata.json must be an object keyed by module name")
        blob = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
        parts += ['<script type="application/json" id="refdata">', blob, "</script>",
                  "<script>", read("reference-viewer.js"), "</script>"]
    parts += ["<script>", read("tech-toggle.js"), "</script></body></html>"]

    out = pathlib.Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    text = "\n".join(parts)
    out.write_text(text, encoding="utf-8")
    size = len(text.encode("utf-8"))
    print(f"wrote {out} ({size/1024:.0f} KB)")
    if size > 16 * 1024 * 1024:
        sys.exit("ERROR: file is over the 16 MB publishing limit; trim the logic reference")

if __name__ == "__main__":
    main()
