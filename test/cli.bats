#!/usr/bin/env bats
# CLI-level tests — exercise main() end-to-end (arg parsing, mode dispatch,
# config resolution, --dsp guardrails) against mocked docker/devcontainer/gh
# so no real container is ever built.

load test_helper

setup() {
  source_dco
  use_mocks
  WS="$(new_workspace)"
}

# ── help / list ───────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run main --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "--list shells out to docker ps with the devcontainer label filter" {
  run main --list
  [ "$status" -eq 0 ]
  mock_called_with "label=devcontainer.local_folder"
}

# ── path validation ───────────────────────────────────────────────────────

@test "dies on a workspace path that doesn't exist" {
  run main "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a directory"* ]]
}

# ── stop mode ─────────────────────────────────────────────────────────────

@test "--stop dies when no container is found for the workspace" {
  run main "$WS" --stop
  [ "$status" -eq 1 ]
  [[ "$output" == *"no container found"* ]]
}

@test "--stop removes the container when one is found" {
  MOCK_DOCKER_CONTAINER_ID="abc123" run main "$WS" --stop
  [ "$status" -eq 0 ]
  mock_called_with "docker rm -f abc123"
}

# ── config resolution / scaffolding ───────────────────────────────────────

@test "auto-scaffolds a default .devcontainer when none exists, then brings it up" {
  run main "$WS"
  [ "$status" -eq 0 ]
  [ -f "$WS/.devcontainer/devcontainer.json" ]
  mock_called_with "devcontainer up"
}

@test "uses an existing top-level .devcontainer/devcontainer.json without rescaffolding" {
  mkdir -p "$WS/.devcontainer"
  echo '{"marker":"existing"}' > "$WS/.devcontainer/devcontainer.json"
  run main "$WS"
  [ "$status" -eq 0 ]
  run cat "$WS/.devcontainer/devcontainer.json"
  [[ "$output" == *"existing"* ]]
}

@test "scaffolds the shipped 'autonomous' sub-config on first use" {
  run main "$WS" autonomous
  [ "$status" -eq 0 ]
  [ -f "$WS/.devcontainer/autonomous/devcontainer.json" ]
}

@test "dies with the list of shipped profiles for an unknown sub-config name" {
  run main "$WS" not-a-real-profile
  [ "$status" -eq 1 ]
  [[ "$output" == *"no shipped profile named 'not-a-real-profile'"* ]]
  [[ "$output" == *"autonomous"* ]]
}

@test "lists multiple named sub-configs and exits 1 when none is specified" {
  mkdir -p "$WS/.devcontainer/staging" "$WS/.devcontainer/prod"
  echo '{}' > "$WS/.devcontainer/staging/devcontainer.json"
  echo '{}' > "$WS/.devcontainer/prod/devcontainer.json"
  run main "$WS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"multiple configs found"* ]]
  [[ "$output" == *"staging"* ]]
  [[ "$output" == *"prod"* ]]
}

# ── regen mode ────────────────────────────────────────────────────────────

@test "--regen refreshes an existing .devcontainer from templates" {
  mkdir -p "$WS/.devcontainer"
  echo 'stale' > "$WS/.devcontainer/devcontainer.json"
  run main "$WS" --regen
  [ "$status" -eq 0 ]
  run cat "$WS/.devcontainer/devcontainer.json"
  [[ "$output" != "stale" ]]
}

# ── --dsp guardrails ──────────────────────────────────────────────────────

@test "--dsp dies when the workspace is not a git repo" {
  run main "$WS" --dsp
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs"*"to already be a git repo"* ]]
}

@test "--dsp dies non-interactively when there's no GitHub remote" {
  git -C "$WS" init -q
  run main "$WS" --dsp < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"no GitHub remote"* ]]
}

@test "--dsp dies when the resolved allowlist has no active entries" {
  git -C "$WS" init -q
  git -C "$WS" remote add origin "https://github.com/blakeboswell/dco.git"
  run main "$WS" --dsp < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"no active entries"* ]]
}

@test "--dsp dies non-interactively when DCO_GITHUB_TOKEN is unset, even with a good allowlist" {
  git -C "$WS" init -q
  git -C "$WS" remote add origin "https://github.com/blakeboswell/dco.git"
  mkdir -p "$WS/.devcontainer"
  echo "example.com" > "$WS/.devcontainer/allowlist.txt"
  echo '{}' > "$WS/.devcontainer/devcontainer.json"
  unset DCO_GITHUB_TOKEN
  run main "$WS" --dsp < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"DCO_GITHUB_TOKEN is not set"* ]]
}

@test "--dsp proceeds once git remote, allowlist, and token are all satisfied" {
  git -C "$WS" init -q
  git -C "$WS" remote add origin "https://github.com/blakeboswell/dco.git"
  mkdir -p "$WS/.devcontainer"
  echo "example.com" > "$WS/.devcontainer/allowlist.txt"
  echo '{}' > "$WS/.devcontainer/devcontainer.json"
  DCO_GITHUB_TOKEN="fake-token" run main "$WS" --dsp < /dev/null
  [ "$status" -eq 0 ]
  mock_called_with "devcontainer up"
}

# ── git identity sync ─────────────────────────────────────────────────────

@test "syncs host git user.name/user.email into the container via devcontainer exec" {
  # isolate $HOME so `git config --global` writes to a throwaway .gitconfig
  # instead of the real one on whatever machine runs this suite
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  git config --global user.name "Test User"
  git config --global user.email "test@example.com"
  run main "$WS"
  [ "$status" -eq 0 ]
  mock_called_with "git config --global user.name Test User"
  mock_called_with "git config --global user.email test@example.com"
}
