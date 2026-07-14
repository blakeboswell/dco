#!/usr/bin/env bash
# Automates docs/e2e-runbook.md. Each subcommand checks current state
# before acting, so re-running after a failure resumes rather than
# repeating already-done work -- nothing here needs a clean slate to
# re-run, only `setup`'s very first invocation does (an empty workspace
# dir). Run from a real terminal on your host, not from inside a Claude
# session: needs Docker, gh, and a browser for the PAT flow, exactly like
# the manual runbook this wraps. The interactive parts of that flow (repo
# creation confirm, PAT paste, GitHub handle) aren't automated here --
# they're `dco --dsp`'s own prompts, surfaced normally.
#
# Usage:
#   e2e-runbook.sh setup             workspace + git init + GitHub repo + --dsp launch
#   e2e-runbook.sh file-issue        file a test issue, label it 'ready' (idempotent)
#   e2e-runbook.sh check             one-shot status: container/issues/PRs (not a blocking wait)
#   e2e-runbook.sh verify-firewall   confirm default-deny + GitHub access from inside
#   e2e-runbook.sh cleanup           purge container+volumes, delete repo, rm workspace
#   e2e-runbook.sh all               setup + file-issue, then print next steps
#
# Workspace defaults to ~/tmp/test-dco; override with DCO_E2E_WORKSPACE.
set -euo pipefail

WORKSPACE="${DCO_E2E_WORKSPACE:-$HOME/tmp/test-dco}"

die()  { echo "e2e-runbook: error: $*" >&2; exit 1; }
info() { echo "e2e-runbook: $*" >&2; }

require() {
  command -v "$1" &>/dev/null || die "$1 is required but not found on PATH"
}

# best-effort "owner/repo" for the workspace's origin remote; empty if none
gh_owner_repo() {
  local url
  url="$(git -C "$WORKSPACE" remote get-url origin 2>/dev/null || true)"
  [[ -n "$url" ]] || return 1
  url="${url%.git}"
  case "$url" in
    git@github.com:*)       echo "${url#git@github.com:}" ;;
    ssh://git@github.com/*) echo "${url#ssh://git@github.com/}" ;;
    https://github.com/*)   echo "${url#https://github.com/}" ;;
    *) return 1 ;;
  esac
}

warn_if_dco_stale() {
  dco --help 2>&1 | grep -q -- "--sub-config" || \
    info "warning: installed 'dco' looks stale (no --sub-config in --help). Reinstall: curl -fsSL https://raw.githubusercontent.com/blakeboswell/dco/main/install.sh | sh"
}

cmd_setup() {
  require docker
  require dco
  require gh
  require git
  warn_if_dco_stale

  if [[ ! -d "$WORKSPACE" ]]; then
    info "creating $WORKSPACE"
    mkdir -p "$WORKSPACE"
  fi

  if [[ ! -d "$WORKSPACE/.git" ]]; then
    info "git init"
    git -C "$WORKSPACE" init -q
  fi

  if ! git -C "$WORKSPACE" rev-parse HEAD &>/dev/null; then
    info "no commits yet -- creating an initial one"
    [[ -f "$WORKSPACE/README.md" ]] || echo "# $(basename "$WORKSPACE")" > "$WORKSPACE/README.md"
    git -C "$WORKSPACE" add README.md
    git -C "$WORKSPACE" commit -q -m "initial commit"
  fi

  info "launching dco --dsp (interactive: prompts for repo creation / PAT paste / handle will surface normally if needed)"
  ( cd "$WORKSPACE" && dco --dsp )
  info "done. 'dco --list' to confirm the container's up; reattach any time with 'dco --sub-config autonomous'."
}

cmd_file_issue() {
  require gh
  [[ -d "$WORKSPACE/.git" ]] || die "no workspace at $WORKSPACE yet -- run 'setup' first"
  local owner_repo
  owner_repo="$(gh_owner_repo)" || die "no GitHub remote configured for $WORKSPACE yet -- run 'setup' first"

  local existing
  existing="$(gh issue list --repo "$owner_repo" --search "Hello world in:title" --state open \
    --json number --jq '.[0].number // empty' 2>/dev/null || true)"

  local issue_number
  if [[ -n "$existing" ]]; then
    info "reusing existing open issue #$existing"
    issue_number="$existing"
  else
    local issue_url
    issue_url="$(gh issue create --repo "$owner_repo" \
      --title "Hello world" \
      --body "Add a hello.txt file to the repo root containing the text 'hello world'.")"
    issue_number="${issue_url##*/}"
    info "created issue #$issue_number: $issue_url"
  fi

  gh issue edit "$issue_number" --repo "$owner_repo" --add-label ready >/dev/null
  info "labeled #$issue_number 'ready' on $owner_repo"
}

cmd_check() {
  require gh
  require docker
  [[ -d "$WORKSPACE/.git" ]] || die "no workspace at $WORKSPACE yet -- run 'setup' first"
  local owner_repo
  owner_repo="$(gh_owner_repo)" || die "no GitHub remote configured for $WORKSPACE yet -- run 'setup' first"

  echo "--- container ($WORKSPACE) ---"
  docker ps --filter "label=devcontainer.local_folder=$WORKSPACE" \
    --format "table {{.Names}}\t{{.Status}}" || true

  echo "--- issues ($owner_repo) ---"
  gh issue list --repo "$owner_repo" --state all \
    --json number,title,labels,updatedAt \
    --jq '.[] | "#\(.number) \(.title) [\([.labels[].name] | join(","))] updated \(.updatedAt)"' \
    || echo "(failed to list issues)"

  echo "--- pull requests ($owner_repo) ---"
  gh pr list --repo "$owner_repo" --state all \
    --json number,title,reviewDecision \
    --jq '.[] | "#\(.number) \(.title) reviewDecision=\(.reviewDecision // "PENDING")"' \
    || echo "(failed to list PRs)"
}

cmd_verify_firewall() {
  require devcontainer
  local config="$WORKSPACE/.devcontainer/autonomous/devcontainer.json"
  [[ -f "$config" ]] || die "no autonomous profile at $config yet -- run 'setup' first"
  local owner_repo
  owner_repo="$(gh_owner_repo || true)"

  info "checking a non-allowlisted domain is blocked (expect this to fail/time out)..."
  if devcontainer exec --workspace-folder "$WORKSPACE" --config "$config" \
       -- curl -s -o /dev/null --max-time 5 https://example.com &>/dev/null; then
    info "WARNING: example.com was reachable -- the firewall may not be enforcing"
  else
    info "OK: example.com is blocked, as expected"
  fi

  info "checking GitHub access still works..."
  if [[ -n "$owner_repo" ]] && devcontainer exec --workspace-folder "$WORKSPACE" --config "$config" \
       -- gh issue list --repo "$owner_repo" &>/dev/null; then
    info "OK: gh issue list succeeded from inside the container"
  else
    info "WARNING: gh issue list failed from inside the container -- check GH_TOKEN/network"
  fi
}

cmd_cleanup() {
  require dco
  require gh

  local owner_repo=""
  [[ -d "$WORKSPACE/.git" ]] && owner_repo="$(gh_owner_repo || true)"

  if [[ -d "$WORKSPACE" ]]; then
    ( cd "$WORKSPACE" && dco --purge ) || true
  fi

  if [[ -n "$owner_repo" ]]; then
    local reply=""
    read -r -p "e2e-runbook: delete GitHub repo $owner_repo? [y/N] " reply || true
    [[ "$reply" =~ ^[Yy]$ ]] && gh repo delete "$owner_repo" --yes
  fi

  local reply=""
  read -r -p "e2e-runbook: remove local workspace $WORKSPACE? [y/N] " reply || true
  [[ "$reply" =~ ^[Yy]$ ]] && rm -rf "$WORKSPACE"

  info "remember to revoke the PAT by hand: https://github.com/settings/personal-access-tokens"
}

cmd_all() {
  cmd_setup
  cmd_file_issue
  info ""
  info "Setup complete. Next:"
  info "  $0 check              # snapshot current issue/PR/container state"
  info "  $0 verify-firewall    # confirm default-deny + GitHub access"
  info "  $0 cleanup            # tear everything down when done"
}

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \?//'
}

case "${1:-}" in
  setup)            cmd_setup ;;
  file-issue)       cmd_file_issue ;;
  check)            cmd_check ;;
  verify-firewall)  cmd_verify_firewall ;;
  cleanup)          cmd_cleanup ;;
  all)              cmd_all ;;
  -h|--help|help|"") usage ;;
  *) echo "e2e-runbook: unknown command: $1" >&2; usage; exit 1 ;;
esac
