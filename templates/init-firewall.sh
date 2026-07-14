#!/bin/bash
# This is the only copy: any sub-config that points its "dockerfile" at
# ../Dockerfile (the way the default profile's own config does) shares this
# same top-level Dockerfile, since `devcontainer` CLI resolves the build
# context to wherever that dockerfile path actually lands — the top-level
# .devcontainer/, not .devcontainer/<name>/. So the Dockerfile's
# `COPY init-firewall.sh` is always this file, for every profile. Don't add
# a per-profile copy under templates/<name>/: it would look editable/
# profile-specific but silently never be read. `dco --regen` (which only
# refreshes the top-level .devcontainer/) is therefore sufficient to update
# this for every profile — no per-sub-config regen needed for this file.
set -euo pipefail
IFS=$'\n\t'

ALLOWLIST_FILE="/usr/local/etc/dco-allowlist.txt"

# Empty allowlist (after stripping comments/blanks) = fully disabled,
# byte-identical to a no-op. Must be checked before any iptables/ipset
# command runs below.
mapfile -t ALLOWED_DOMAINS < <(grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST_FILE" 2>/dev/null || true)
if [ "${#ALLOWED_DOMAINS[@]}" -eq 0 ]; then
  exit 0
fi

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Create ipset with CIDR support
ipset create allowed-domains hash:net

# Fetch GitHub meta information and aggregate + add their IP ranges.
# GitHub is always allowed once enforcement is active — git/gh need it
# regardless of what's in the user's allowlist. Retried a few times before
# giving up: this is core to the whole workflow (unlike an individual
# allowlist domain below), so it stays fatal, but a transient network blip
# shouldn't be treated the same as GitHub's API actually being unreachable.
echo "Fetching GitHub IP ranges..."
gh_ranges=""
for attempt in 1 2 3; do
    gh_ranges=$(curl -s https://api.github.com/meta)
    [ -n "$gh_ranges" ] && break
    echo "  attempt $attempt/3 failed, retrying..."
    sleep 2
done
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
# allowed-domains is an IPv4-only ipset (hash:net, no `family inet6`) and
# there's no ip6tables enforcement below, so IPv6 ranges are filtered out
# here explicitly rather than left to fail (or be silently dropped by
# `aggregate`) further down.
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    ipset add allowed-domains "$cidr" -exist
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$' | aggregate -q)

# Resolve and add domains from the allowlist. Retried a few times, then
# skipped (not fatal) if it still won't resolve: a single flaky domain
# (transient DNS blip, or a non-critical one like a telemetry endpoint)
# shouldn't take down the whole container — it just stays unreachable,
# which is fail-safe (still default-deny) rather than fail-open.
for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "Resolving $domain..."
    ips=""
    for attempt in 1 2 3; do
        ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
        [ -n "$ips" ] && break
        echo "  attempt $attempt/3 failed, retrying..."
        sleep 2
    done
    if [ -z "$ips" ]; then
        echo "WARNING: failed to resolve $domain after 3 attempts — skipping it (it will be unreachable, not the whole firewall)"
        continue
    fi

    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Adding $ip for $domain"
        ipset add allowed-domains "$ip" -exist
    done <<< "$ips"
done

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies to DROP first
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
