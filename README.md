# olyahyai.dev

Portfolio and résumé of Omar Lyahyai, bilingual EN/FR, built with [Hugo](https://gohugo.io/) and deployed to Cloudflare Pages.

| URL | Content |
|---|---|
| `/` · `/fr/` | Home page |
| `/cv/` · `/fr/cv/` | Résumé (HTML) |
| `/cv/en.pdf` · `/cv/fr.pdf` | Résumé (PDF, printed by headless Chrome in CI) |

## How it is published

```
Forgejo (homelab, source of truth) ──push-mirror──▶ GitHub ──Actions──▶ Cloudflare Pages
   review/merge on Forgejo              build only        main  → olyahyai.dev
                                                          other → <branch>.olyahyai-dev.pages.dev
```

Nothing is ever pushed straight to `main`: changes go through a pull request on Forgejo, and the preview URL of the branch is checked before merging.

## Layout

```
hugo.toml              languages (en default at /, fr at /fr/), params
content/               home page text and project list (front matter), CV page stubs;
                       case-studies/, articles/, projects/ are generated from Notion (see below)
data/cv.json           CV facts (Notion « CV — Faits »), generated — do not edit by hand
layouts/               baseof + home (no theme); cv.html renders data/cv.json with the A4 print CSS
assets/css/main.css    the only stylesheet of the site (light/dark)
static/cv/photo.jpg    profile photo shared by the CV and the home page
static/_headers        Cloudflare Pages security headers (CSP, HSTS, ...)
scripts/build-pdf.sh   prints /cv/ and /fr/cv/ to public/cv/{en,fr}.pdf
.github/workflows/     gitleaks (pinned binary, full history) → Hugo (pinned, checksum) → PDFs (must be 2 pages) → Cloudflare Pages
                       (the Pages project is created on the first run if it does not exist)
```

## Local build

```sh
hugo server                 # http://localhost:1313
hugo --gc --minify && scripts/build-pdf.sh   # needs Chrome/Chromium
```

## Content pipeline (no manual step)

Notion (« Portfolio — Espace Scribe ») → notion-sync → Forgejo `content` (PR `sync/notion`)
→ publisher-gate (leak scan, locked CV sections, numbers grounded in sources, site build on a
`auto/*` preview branch) → merge + fast-forward of `main` here → Cloudflare Pages.
`data/cv.json`, `content/case-studies|articles|projects/*.md` and `static/images/` are written
by the gate; hand-written files (layouts, `_index` pages, home text) are never touched.

## Secrets

None in this repository. The CI needs two GitHub Actions secrets:

| Secret | Scope |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Account API token, Cloudflare Pages → Edit only, 1-year expiry |
| `CLOUDFLARE_ACCOUNT_ID` | not secret strictly speaking, kept with the token |
