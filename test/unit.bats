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

# ── url_encode ────────────────────────────────────────────────────────────

@test "url_encode replaces spaces with +" {
  run url_encode "dco autonomous mode"
  [ "$output" = "dco+autonomous+mode" ]
}

@test "url_encode is a no-op on strings without spaces" {
  run url_encode "no-spaces-here"
  [ "$output" = "no-spaces-here" ]
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
  run project_id "/home/me/projects/api" "autonomous"
  [[ "$output" == *-autonomous ]]
}

@test "project_id sanitizes non-alphanumeric characters in the slug" {
  run project_id "/home/me/projects/my api!"
  [[ "$output" != *[!a-zA-Z0-9_.-]* ]]
}

# ── github_owner_repo ─────────────────────────────────────────────────────

setup_git_remote() {
  local dir="$BATS_TEST_TMPDIR/repo-$RANDOM"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$1"
  printf '%s' "$dir"
}

@test "github_owner_repo parses an https remote" {
  dir="$(setup_git_remote "https://github.com/blakeboswell/dco.git")"
  run github_owner_repo "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "blakeboswell/dco" ]
}

@test "github_owner_repo parses an ssh (scp-style) remote" {
  dir="$(setup_git_remote "git@github.com:blakeboswell/dco.git")"
  run github_owner_repo "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "blakeboswell/dco" ]
}

@test "github_owner_repo parses an ssh:// remote" {
  dir="$(setup_git_remote "ssh://git@github.com/blakeboswell/dco.git")"
  run github_owner_repo "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "blakeboswell/dco" ]
}

@test "github_owner_repo fails on a non-github remote" {
  dir="$(setup_git_remote "https://gitlab.com/blakeboswell/dco.git")"
  run github_owner_repo "$dir"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "github_owner_repo fails when there is no origin remote" {
  dir="$BATS_TEST_TMPDIR/no-remote"
  mkdir -p "$dir"
  git -C "$dir" init -q
  run github_owner_repo "$dir"
  [ "$status" -eq 1 ]
}

# ── substitute_github_handle ──────────────────────────────────────────────

@test "substitute_github_handle replaces the placeholder when the var is set" {
  file="$BATS_TEST_TMPDIR/CLAUDE.md"
  echo 'mention {{DCO_GITHUB_HANDLE}} on review' > "$file"
  DCO_GITHUB_HANDLE="octocat" substitute_github_handle "$file"
  run cat "$file"
  [ "$output" = "mention octocat on review" ]
}

@test "substitute_github_handle is a no-op when the file doesn't exist" {
  run substitute_github_handle "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 0 ]
}

@test "substitute_github_handle is a no-op when the var is unset" {
  file="$BATS_TEST_TMPDIR/CLAUDE.md"
  echo 'mention {{DCO_GITHUB_HANDLE}} on review' > "$file"
  unset DCO_GITHUB_HANDLE
  substitute_github_handle "$file"
  run cat "$file"
  [ "$output" = "mention {{DCO_GITHUB_HANDLE}} on review" ]
}

@test "substitute_github_handle is a no-op when there's no placeholder" {
  file="$BATS_TEST_TMPDIR/CLAUDE.md"
  echo 'no placeholder in here' > "$file"
  DCO_GITHUB_HANDLE="octocat" substitute_github_handle "$file"
  run cat "$file"
  [ "$output" = "no placeholder in here" ]
}

# ── scaffold_devcontainer / scaffold_named_subconfig ─────────────────────

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
  dest="$BATS_TEST_TMPDIR/.devcontainer"
  mkdir -p "$dest/autonomous"
  echo "hand-customized" > "$dest/autonomous/CLAUDE.md"
  scaffold_devcontainer "$dest"
  [ -f "$dest/devcontainer.json" ]
  run cat "$dest/autonomous/CLAUDE.md"
  [ "$output" = "hand-customized" ]
}

@test "scaffold_named_subconfig scaffolds a shipped profile" {
  dest="$BATS_TEST_TMPDIR/.devcontainer/autonomous"
  run scaffold_named_subconfig "autonomous" "$dest"
  [ "$status" -eq 0 ]
  [ -f "$dest/devcontainer.json" ]
  [ -x "$dest/init-firewall.sh" ]
}

@test "scaffold_named_subconfig returns 1 for an unknown profile, without dying" {
  run scaffold_named_subconfig "does-not-exist" "$BATS_TEST_TMPDIR/.devcontainer/nope"
  [ "$status" -eq 1 ]
  [ ! -d "$BATS_TEST_TMPDIR/.devcontainer/nope" ]
}

@test "scaffold_named_subconfig substitutes the github handle into CLAUDE.md" {
  dest="$BATS_TEST_TMPDIR/.devcontainer/autonomous"
  DCO_GITHUB_HANDLE="octocat" scaffold_named_subconfig "autonomous" "$dest"
  grep -q "octocat" "$dest/CLAUDE.md"
}
