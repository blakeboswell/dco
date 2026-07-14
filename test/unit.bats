#!/usr/bin/env bats
# Unit tests for dco.in's standalone helper functions — no Docker, no
# devcontainer CLI, no network. Each sources dco.in fresh via source_dco
# (see test_helper.bash) and calls a function directly.

load test_helper

setup() {
  source_dco
}

# ── die / info ────────────────────────────────────────────────────────────

@test "die prints to stderr prefixed and exits 1" {
  run die "boom"
  [ "$status" -eq 1 ]
  [ "$output" = "dco: error: boom" ]
}

@test "info prints to stderr prefixed and does not exit" {
  run info "hello"
  [ "$status" -eq 0 ]
  [ "$output" = "dco: hello" ]
}

# ── slugify ───────────────────────────────────────────────────────────────

@test "slugify replaces characters outside the given class with -" {
  run slugify "my api!" 'a-zA-Z0-9_.-'
  [ "$output" = "my-api-" ]
}

@test "slugify does not corrupt a clean basename" {
  run slugify "api" 'a-zA-Z0-9_.-'
  [ "$output" = "api" ]
}

@test "slugify honors a narrower character class (no dot/underscore)" {
  run slugify "my_repo.name" 'a-zA-Z0-9-'
  [ "$output" = "my-repo-name" ]
}

# ── project_id ────────────────────────────────────────────────────────────

@test "project_id is stable for the same workspace" {
  run project_id "/home/me/projects/api"
  first="$output"
  run project_id "/home/me/projects/api"
  [ "$output" = "$first" ]
}

@test "project_id differs for two dirs sharing a basename" {
  run project_id "/home/me/projects/api"
  a="$output"
  run project_id "/home/me/other/api"
  [ "$output" != "$a" ]
}

@test "project_id appends a sub-config slug when given one" {
  run project_id "/home/me/projects/api" "gpu-trading"
  [[ "$output" == *-gpu-trading ]]
}

@test "project_id sanitizes non-alphanumeric characters in the slug" {
  run project_id "/home/me/projects/my api!"
  [[ "$output" != *[!a-zA-Z0-9_.-]* ]]
}

# ── scaffold_devcontainer ──────────────────────────────────────────────────

@test "scaffold_devcontainer copies templates and config into dest" {
  dest="$BATS_TEST_TMPDIR/.devcontainer"
  scaffold_devcontainer "$dest"
  [ -f "$dest/devcontainer.json" ]
  [ -f "$dest/Dockerfile" ]
  [ -f "$dest/allowlist.txt" ]
  [ -x "$dest/init-firewall.sh" ]
}

@test "scaffold_devcontainer dies when SHAREDIR has no templates" {
  SHAREDIR="$BATS_TEST_TMPDIR/empty-sharedir"
  mkdir -p "$SHAREDIR"
  run scaffold_devcontainer "$BATS_TEST_TMPDIR/.devcontainer"
  [ "$status" -eq 1 ]
  [[ "$output" == *"template dir not found"* ]]
}

@test "scaffold_devcontainer does not touch an existing named sub-config directory" {
  # simulates a project that has committed its own .devcontainer/<name>/,
  # e.g. as described in the --sub-config help text
  dest="$BATS_TEST_TMPDIR/.devcontainer"
  mkdir -p "$dest/custom"
  echo "hand-customized" > "$dest/custom/devcontainer.json"
  scaffold_devcontainer "$dest"
  [ -f "$dest/devcontainer.json" ]
  run cat "$dest/custom/devcontainer.json"
  [ "$output" = "hand-customized" ]
}

# ── scaffold self-consistency ─────────────────────────────────────────────
# Static check with zero Docker/network involved: does a freshly scaffolded
# devcontainer.json's "dockerfile" actually resolve to a file that exists?
# This is exactly the class of bug that twice took a multi-minute real
# Docker cycle to surface (a shared top-level Dockerfile missing because a
# named sub-config was scaffolded without it) -- checkable in milliseconds
# instead, so it doesn't need a live e2e run to catch again.

# prints why it failed on stderr before returning 1, since plain bats-core
# (no bats-assert loaded) has no `fail`-with-message builtin; any nonzero
# return from a direct call in a test body fails that test, same as `run`
# would, and bats shows this output alongside the failure
assert_dockerfile_resolves() {
  local devcontainer_json="$1" dockerfile resolved
  dockerfile="$(jq -r '.build.dockerfile // empty' "$devcontainer_json")"
  if [[ -z "$dockerfile" ]]; then
    echo "no .build.dockerfile in $devcontainer_json" >&2
    return 1
  fi
  resolved="$(dirname "$devcontainer_json")/$dockerfile"
  if [[ ! -f "$resolved" ]]; then
    echo "$devcontainer_json points \"dockerfile\": \"$dockerfile\" at $resolved, which doesn't exist" >&2
    return 1
  fi
}

@test "the default profile's scaffolded dockerfile reference resolves" {
  command -v jq &>/dev/null || skip "jq not installed"
  dest="$BATS_TEST_TMPDIR/.devcontainer"
  scaffold_devcontainer "$dest"
  assert_dockerfile_resolves "$dest/devcontainer.json"
}

@test "a custom sub-config sharing the top-level Dockerfile resolves once scaffold_devcontainer has run" {
  # mirrors main()'s actual sequence for a workspace that's never had the
  # default profile scaffolded: the shared top-level files have to be
  # created before a sub-config that points "dockerfile" at ../Dockerfile
  # can build. This project's own .devcontainer/<name>/ is committed by
  # the user, not scaffolded by dco -- simulated here directly.
  command -v jq &>/dev/null || skip "jq not installed"
  dest="$BATS_TEST_TMPDIR/.devcontainer"
  scaffold_devcontainer "$dest"
  mkdir -p "$dest/custom"
  echo '{"build":{"dockerfile":"../Dockerfile"}}' > "$dest/custom/devcontainer.json"
  assert_dockerfile_resolves "$dest/custom/devcontainer.json"
}

@test "the default profile's dockerfile reference resolves against the source templates" {
  # catches the same bug class one step earlier: even before anything is
  # scaffolded into a project, does templates/devcontainer.json's own
  # "dockerfile" path resolve within templates/ itself?
  command -v jq &>/dev/null || skip "jq not installed"
  assert_dockerfile_resolves "$SHAREDIR/templates/devcontainer.json"
}
