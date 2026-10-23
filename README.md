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
content/               home page text and project list (front matter), CV page stubs
layouts/               baseof + home (no theme), cv.html serves assets/cv/cv.<lang>.html as is
assets/cv/             the résumé, one self-contained HTML per language (A4 print CSS)
assets/css/main.css    the only stylesheet of the site (light/dark)
static/cv/photo.jpg    profile photo shared by the CV and the home page
static/_headers        Cloudflare Pages security headers (CSP, HSTS, ...)
scripts/build-pdf.sh   prints /cv/ and /fr/cv/ to public/cv/{en,fr}.pdf
tools/import-cv.py     P0 only: imports the hand-written CV (will be replaced by data/cv.yaml in P3)
.github/workflows/     gitleaks (pinned binary, full history) → Hugo (pinned, checksum) → PDFs → Cloudflare Pages
                       (the Pages project is created on the first run if it does not exist)
```

## Local build

```sh
hugo server                 # http://localhost:1313
hugo --gc --minify && scripts/build-pdf.sh   # needs Chrome/Chromium
```

## Updating the résumé (until P3)

Edit the source HTML in `HomeLab/CV-2026-10/`, then:

```sh
python3 tools/import-cv.py "<path>/HomeLab/CV-2026-10"
```

The script stops if an expected snippet is missing, so a change in the source is never silently dropped.

## Secrets

None in this repository. The CI needs two GitHub Actions secrets:

| Secret | Scope |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Account API token, Cloudflare Pages → Edit only, 1-year expiry |
| `CLOUDFLARE_ACCOUNT_ID` | not secret strictly speaking, kept with the token |
