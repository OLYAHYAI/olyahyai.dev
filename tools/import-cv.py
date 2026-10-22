#!/usr/bin/env python3
"""Import the hand-written CV (HomeLab/CV-2026-10) into the site.

P0 only: the CV is still maintained by hand. In P3 it will be generated from
data/cv.yaml and this script will go away.

Usage: python3 tools/import-cv.py <dir containing CV_Omar_LYAHYAI_{EN,FR}.html>

- extracts the embedded photo to static/cv/photo.jpg (one file, shared by EN/FR)
- points the portfolio link to olyahyai.dev and drops the jbr.ma contact line
- marks JBR.ma as a past project (decision of 22/10/2026)
- writes assets/cv/cv.en.html and assets/cv/cv.fr.html
The script fails loudly if an expected snippet is missing, so a change in the
source CV cannot be silently ignored.
"""
import base64, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else None
if not SRC or not SRC.is_dir():
    sys.exit(__doc__)

COMMON = [
    ('<a href="https://portfolio.olyhome.site">portfolio.olyhome.site</a>',
     '<a href="https://olyahyai.dev">olyahyai.dev</a>'),
]
EDITS = {
    "en": COMMON + [
        ('<span class="c-label">Project</span><span class="c-value"><a href="https://jbr.ma">jbr.ma</a></span>\n', ''),
        ('JBR.ma — E-commerce SaaS platform</div><div class="item-meta">2025 – Present',
         'JBR.ma — E-commerce SaaS platform</div><div class="item-meta">2025 – 2026'),
        ('An Android app is on Google Play.', 'An Android app was published on Google Play.'),
        ('The containerized backend runs in LXC', 'The containerized backend ran in LXC'),
        ('Traffic goes through Cloudflare Tunnels', 'Traffic went through Cloudflare Tunnels'),
        ('Datadog and Sentry monitor the platform.', 'Datadog and Sentry monitored the platform.'),
    ],
    "fr": COMMON + [
        ('<span class="c-label">Projet</span><span class="c-value"><a href="https://jbr.ma">jbr.ma</a></span>\n', ''),
        ("JBR.ma — Plateforme SaaS e-commerce</div><div class=\"item-meta\">2025 – Aujourd'hui",
         'JBR.ma — Plateforme SaaS e-commerce</div><div class="item-meta">2025 – 2026'),
        ('Application Android disponible sur Google Play.', 'Application Android publiée sur Google Play.'),
    ],
}

photo_written = False
for lang, edits in EDITS.items():
    html = (SRC / f"CV_Omar_LYAHYAI_{lang.upper()}.html").read_text(encoding="utf-8")
    m = re.search(r'data:image/jpeg;base64,([A-Za-z0-9+/=]+)', html)
    if not m:
        sys.exit(f"[{lang}] embedded photo not found")
    if not photo_written:
        (ROOT / "static/cv/photo.jpg").write_bytes(base64.b64decode(m.group(1)))
        photo_written = True
    html = html.replace(m.group(0), "/cv/photo.jpg")
    for old, new in edits:
        if old not in html:
            sys.exit(f"[{lang}] expected snippet not found: {old[:70]}...")
        html = html.replace(old, new)
    # PDF links for the screen version (hidden when printing)
    pdf = '/cv/en.pdf' if lang == 'en' else '/cv/fr.pdf'
    other = ('/fr/cv/', 'Version française') if lang == 'en' else ('/cv/', 'English version')
    label = 'Download PDF' if lang == 'en' else 'Télécharger le PDF'
    bar = (f'<nav class="cv-bar"><a href="{"/" if lang == "en" else "/fr/"}">← olyahyai.dev</a>'
           f'<a href="{pdf}">{label}</a><a href="{other[0]}" hreflang="{"fr" if lang == "en" else "en"}">{other[1]}</a></nav>\n')
    css = ('  .cv-bar { max-width: 210mm; margin: 6mm auto 0; display: flex; gap: 6mm; font-size: 13px; }\n'
           '  @media print { .cv-bar { display: none; } }\n</style>')
    html = html.replace('</style>', css, 1).replace('<body>\n', '<body>\n' + bar, 1)
    (ROOT / f"assets/cv/cv.{lang}.html").write_text(html, encoding="utf-8")
    print(f"[{lang}] ok")
