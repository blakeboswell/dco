#!/usr/bin/env bash
# Resolves every domain in the shipped allowlist to catch a dead or
# renamed entry before it ships, rather than discovering it later as a
# firewall failure inside a locked-down container -- where the only
# feedback is "ERROR: failed to resolve X", with no way to tell a
# genuinely dead domain from a transient blip. That distinction mattered
# in practice: a since-removed autonomous-mode allowlist entry sat
# returning NXDOMAIN from every resolver, permanently, until a version of
# this check caught it.
#
# Needs real network access and `dig`; deliberately not part of `make
# test`, which is fully mocked and needs neither. Skips (not a hard
# failure) if `dig` isn't installed, since this is a supplementary check,
# not a build requirement.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v dig &>/dev/null; then
  echo "check-allowlist-domains: 'dig' not found, skipping (install dnsutils/bind-utils to enable this check)" >&2
  exit 0
fi

failed=0
for f in config/allowlist.txt; do
  while IFS= read -r domain; do
    [[ -z "$domain" ]] && continue
    if dig +short +time=3 +tries=2 A "$domain" 2>/dev/null | grep -q .; then
      echo "OK   $domain ($f)"
    else
      echo "FAIL $domain ($f) -- does not resolve"
      failed=1
    fi
  done < <(grep -vE '^[[:space:]]*(#|$)' "$f")
done

exit "$failed"
