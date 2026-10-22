#!/usr/bin/env bash
# Print the CV pages of an already built site (public/) to PDF with headless Chromium.
# Output: public/cv/en.pdf and public/cv/fr.pdf
# Usage: scripts/build-pdf.sh [chromium-binary]   (default: $CHROME, then google-chrome, then chromium)
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="${1:-${CHROME:-$(command -v google-chrome || command -v chromium || true)}}"
[ -x "$CHROME" ] || { echo "Chromium not found" >&2; exit 1; }
[ -f public/cv/index.html ] || { echo "Run hugo first" >&2; exit 1; }

PORT=8765
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory public >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do curl -fsS "http://127.0.0.1:$PORT/cv/" >/dev/null 2>&1 && break; sleep 0.1; done

print() { # $1 = URL path, $2 = output file
  "$CHROME" --headless=new --no-sandbox --disable-gpu --no-pdf-header-footer \
    --run-all-compositor-stages-before-draw --virtual-time-budget=5000 \
    --print-to-pdf="$2" "http://127.0.0.1:$PORT$1" 2>/dev/null
  [ -s "$2" ] || { echo "PDF not produced: $2" >&2; exit 1; }
  echo "ok $2 ($(stat -c%s "$2") bytes)"
}
print /cv/    public/cv/en.pdf
print /fr/cv/ public/cv/fr.pdf
