#!/usr/bin/env bash
# Deterministic leak check for everything that ends up on the public site.
# Fails (exit 1) if published sources contain infrastructure details:
#   - private / CGNAT IPv4 addresses (RFC 1918, 100.64.0.0/10 = Tailscale)
#   - Tailscale MagicDNS names (*.ts.net) and tailnet IDs
#   - MAC addresses, Proxmox guest IDs written as "LXC 410" / "VM 122"
#   - anything matching the extra regex in $SENSITIVE_DENYLIST (CI secret, never committed)
#     or in .sensitive-denylist (local file, git-ignored) — e.g. internal host names.
# Documentation ranges (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24) are allowed.
set -euo pipefail
cd "$(dirname "$0")/.."

paths=(content layouts i18n hugo.toml assets/css)
# The hand-written CV is checked too, but its embedded base64 photo was extracted already.
[ -d assets/cv ] && paths+=(assets/cv)

patterns=(
  '(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'
  '(^|[^0-9.])192\.168\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'
  '(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'
  '(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'
  '[A-Za-z0-9-]+\.ts\.net'
  '\btail[0-9a-f]{6}\b'
  '\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b'
  '\b(LXC|VM|CT|VMID|vmid)[ -]?[0-9]{3}\b'
)

extra="${SENSITIVE_DENYLIST:-}"
if [ -z "$extra" ] && [ -f .sensitive-denylist ]; then
  extra="$(grep -v '^\s*#' .sensitive-denylist | grep -v '^\s*$' | paste -sd'|' - || true)"
fi
[ -n "$extra" ] && patterns+=("$extra")

found=0
for p in "${patterns[@]}"; do
  # -I skips binary files; -i only for the user-supplied denylist (host names are case-insensitive)
  flags=(-rInE)
  [ "$p" = "$extra" ] && flags=(-rInEi)
  if out=$(grep "${flags[@]}" -- "$p" "${paths[@]}" 2>/dev/null); then
    if [ "$p" = "$extra" ]; then
      # never echo the private denylist patterns themselves: report file:line only
      echo "$out" | cut -d: -f1,2 | sed 's/$/: matches the private denylist/' >&2
    else
      echo "pattern: ${p}" >&2
      echo "$out" | sed 's/^/  /' >&2
    fi
    found=1
  fi
done

if [ "$found" -ne 0 ]; then
  echo "check-sensitive: infrastructure details found in published sources (see above)." >&2
  exit 1
fi
echo "check-sensitive: OK (${#patterns[@]} patterns, ${paths[*]})"
