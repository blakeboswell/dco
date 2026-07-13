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

# ── purge mode ────────────────────────────────────────────────────────────

@test "--purge exits cleanly with nothing to do when no container or volumes exist" {
  run main "$WS" --purge < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to purge"* ]]
}

@test "--purge removes the container and both named volumes when confirmed" {
  id="$(project_id "$WS")"
  MOCK_DOCKER_CONTAINER_ID="abc123" \
    MOCK_DOCKER_VOLUMES="claude-code-bashhistory-$id claude-code-config-$id" \
    run main "$WS" --purge <<< "y"
  [ "$status" -eq 0 ]
  mock_called_with "docker rm -f abc123"
  mock_called_with "docker volume rm claude-code-bashhistory-$id"
  mock_called_with "docker volume rm claude-code-config-$id"
}

@test "--purge aborts and removes nothing without confirmation" {
  id="$(project_id "$WS")"
  MOCK_DOCKER_CONTAINER_ID="abc123" \
    MOCK_DOCKER_VOLUMES="claude-code-bashhistory-$id claude-code-config-$id" \
    run main "$WS" --purge <<< "n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"purge aborted"* ]]
  ! mock_called_with "docker rm -f abc123"
  ! mock_called_with "docker volume rm"
}

@test "--purge only removes what actually exists (volume already gone)" {
  id="$(project_id "$WS")"
  MOCK_DOCKER_CONTAINER_ID="abc123" \
    MOCK_DOCKER_VOLUMES="claude-code-config-$id" \
    run main "$WS" --purge <<< "y"
  [ "$status" -eq 0 ]
  mock_called_with "docker rm -f abc123"
  mock_called_with "docker volume rm claude-code-config-$id"
  ! mock_called_with "docker volume rm claude-code-bashhistory-$id"
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

@test "scaffolds the shipped 'autonomous' sub-config on first use via --sub-config" {
  run main "$WS" --sub-config autonomous
  [ "$status" -eq 0 ]
  [ -f "$WS/.devcontainer/autonomous/devcontainer.json" ]
}

@test "dies with the list of shipped profiles for an unknown --sub-config name" {
  run main "$WS" --sub-config not-a-real-profile
  [ "$status" -eq 1 ]
  [[ "$output" == *"no shipped profile named 'not-a-real-profile'"* ]]
  [[ "$output" == *"autonomous"* ]]
}

@test "--sub-config dies if given with no value" {
  run main "$WS" --sub-config
  [ "$status" -eq 1 ]
  [[ "$output" == *"--sub-config needs a value"* ]]
}

@test "dies with a migration hint on a stray second positional argument" {
  run main "$WS" autonomous
  [ "$status" -eq 1 ]
  [[ "$output" == *"too many arguments"* ]]
  [[ "$output" == *"--sub-config"* ]]
}

@test "surfaces an existing named sub-config, then still scaffolds the default when none was requested" {
  mkdir -p "$WS/.devcontainer/autonomous"
  echo '{}' > "$WS/.devcontainer/autonomous/devcontainer.json"
  run main "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"also has sub-config(s) here: autonomous"* ]]
  [ -f "$WS/.devcontainer/devcontainer.json" ]
  # the pre-existing sub-config must be untouched, not overwritten by the
  # default-profile scaffold (scaffold_devcontainer skips subdirectories)
  run cat "$WS/.devcontainer/autonomous/devcontainer.json"
  [ "$output" = "{}" ]
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

@test "--dsp warns and dies non-interactively when a container is already running for this profile" {
  MOCK_DOCKER_CONTAINER_ID="abc123" run main "$WS" --dsp < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"already running"* ]]
  [[ "$output" == *"aborted"* ]]
}

@test "--dsp proceeds past the running-container warning when confirmed" {
  git -C "$WS" init -q
  git -C "$WS" remote add origin "https://github.com/blakeboswell/dco.git"
  MOCK_DOCKER_CONTAINER_ID="abc123" DCO_GITHUB_TOKEN="fake-token" \
    run main "$WS" --dsp <<< "y"
  [ "$status" -eq 0 ]
  mock_called_with "devcontainer up"
}

@test "--dsp defaults to the 'autonomous' sub-config when none is given" {
  git -C "$WS" init -q
  git -C "$WS" remote add origin "https://github.com/blakeboswell/dco.git"
  DCO_GITHUB_TOKEN="fake-token" run main "$WS" --dsp < /dev/null
  [ "$status" -eq 0 ]
  [ -f "$WS/.devcontainer/autonomous/devcontainer.json" ]
  # never touches/creates a top-level default profile
  [ ! -f "$WS/.devcontainer/devcontainer.json" ]
}

@test "--sub-config overrides --dsp's autonomous default" {
  git -C "$WS" init -q
  git -C "$WS" remote add origin "https://github.com/blakeboswell/dco.git"
  mkdir -p "$WS/.devcontainer/custom"
  echo "example.com" > "$WS/.devcontainer/custom/allowlist.txt"
  echo '{}' > "$WS/.devcontainer/custom/devcontainer.json"
  DCO_GITHUB_TOKEN="fake-token" run main "$WS" --dsp --sub-config custom < /dev/null
  [ "$status" -eq 0 ]
  mock_called_with "devcontainer up"
  [ ! -d "$WS/.devcontainer/autonomous" ]
}

@test "--dsp dies when the resolved allowlist has no active entries" {
  git -C "$WS" init -q
  git -C "$WS" remote add origin "https://github.com/blakeboswell/dco.git"
  # pre-create the autonomous profile with an emptied allowlist, simulating
  # someone having stripped it down (the shipped one ships pre-populated)
  mkdir -p "$WS/.devcontainer/autonomous"
  : > "$WS/.devcontainer/autonomous/allowlist.txt"
  echo '{}' > "$WS/.devcontainer/autonomous/devcontainer.json"
  run main "$WS" --dsp < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"no active entries"* ]]
}

@test "--dsp dies non-interactively when DCO_GITHUB_TOKEN is unset, even with a good allowlist" {
  git -C "$WS" init -q
  git -C "$WS" remote add origin "https://github.com/blakeboswell/dco.git"
  mkdir -p "$WS/.devcontainer/autonomous"
  echo "example.com" > "$WS/.devcontainer/autonomous/allowlist.txt"
  echo '{}' > "$WS/.devcontainer/autonomous/devcontainer.json"
  unset DCO_GITHUB_TOKEN
  run main "$WS" --dsp < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"DCO_GITHUB_TOKEN is not set"* ]]
}

@test "--dsp proceeds once git remote, allowlist, and token are all satisfied" {
  git -C "$WS" init -q
  git -C "$WS" remote add origin "https://github.com/blakeboswell/dco.git"
  mkdir -p "$WS/.devcontainer/autonomous"
  echo "example.com" > "$WS/.devcontainer/autonomous/allowlist.txt"
  echo '{}' > "$WS/.devcontainer/autonomous/devcontainer.json"
  DCO_GITHUB_TOKEN="fake-token" run main "$WS" --dsp < /dev/null
  [ "$status" -eq 0 ]
  mock_called_with "devcontainer up"
  # the label taxonomy CLAUDE.md depends on gets bootstrapped every launch,
  # not just when the remote was freshly created
  mock_called_with "gh label create ready --repo blakeboswell/dco"
  mock_called_with "gh label create blocked --repo blakeboswell/dco"
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

# ── bootstrap prompt ───────────────────────────────────────────────────────

@test "--dsp launches claude with a bootstrap prompt, as one argument" {
  git -C "$WS" init -q
  git -C "$WS" remote add origin "https://github.com/blakeboswell/dco.git"
  mkdir -p "$WS/.devcontainer/autonomous"
  echo "example.com" > "$WS/.devcontainer/autonomous/allowlist.txt"
  echo '{}' > "$WS/.devcontainer/autonomous/devcontainer.json"
  DCO_GITHUB_TOKEN="fake-token" run main "$WS" --dsp < /dev/null
  [ "$status" -eq 0 ]
  # the whole prompt must survive as a single argument through the
  # composed tmux/bash -lc command line, not get word-split
  mock_called_with "claude --dangerously-skip-permissions Follow\\ your\\ CLAUDE.md\\ operating\\ instructions:"
}

@test "plain --claude (no --dsp) launches claude with no bootstrap prompt" {
  run main "$WS" --claude
  [ "$status" -eq 0 ]
  mock_called_with "tmux new-session -A -s claude claude"
  ! mock_called_with "CLAUDE.md operating instructions"
}
