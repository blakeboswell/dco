#!/usr/bin/env bats
# CLI-level tests — exercise main() end-to-end (arg parsing, mode dispatch,
# config resolution) against mocked docker/devcontainer binaries in
# test/mocks/ so no real container is ever built.

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

@test "--sub-config dies if the named profile doesn't already exist" {
  # dco ships no named profiles of its own -- a sub-config has to already
  # be committed in the project, there's nothing to scaffold it from
  run main "$WS" --sub-config not-a-real-profile
  [ "$status" -eq 1 ]
  [[ "$output" == *"no .devcontainer/not-a-real-profile/devcontainer.json found"* ]]
}

@test "--sub-config dies if given with no value" {
  run main "$WS" --sub-config
  [ "$status" -eq 1 ]
  [[ "$output" == *"--sub-config needs a value"* ]]
}

@test "dies with a migration hint on a stray second positional argument" {
  run main "$WS" custom
  [ "$status" -eq 1 ]
  [[ "$output" == *"too many arguments"* ]]
  [[ "$output" == *"--sub-config"* ]]
}

@test "--sub-config scaffolds the shared top-level files a committed sub-config depends on" {
  # a project commits its own .devcontainer/<name>/devcontainer.json (dco
  # doesn't scaffold this part); if that config shares the top-level
  # ../Dockerfile the way dco's own default profile is laid out, the
  # shared files still need to exist on a genuinely fresh workspace
  mkdir -p "$WS/.devcontainer/custom"
  echo '{"build":{"dockerfile":"../Dockerfile"}}' > "$WS/.devcontainer/custom/devcontainer.json"
  run main "$WS" --sub-config custom
  [ "$status" -eq 0 ]
  [ -f "$WS/.devcontainer/Dockerfile" ]
  [ -f "$WS/.devcontainer/init-firewall.sh" ]
}

@test "--sub-config does not touch an existing customized top-level devcontainer.json" {
  mkdir -p "$WS/.devcontainer/custom"
  echo '{"marker":"hand-customized"}' > "$WS/.devcontainer/devcontainer.json"
  echo '{}' > "$WS/.devcontainer/custom/devcontainer.json"
  run main "$WS" --sub-config custom
  [ "$status" -eq 0 ]
  run cat "$WS/.devcontainer/devcontainer.json"
  [[ "$output" == *"hand-customized"* ]]
  # a hand-edited top-level config might not have a Dockerfile of its own
  # (e.g. an inline "image" instead of a build) -- that's the user's setup
  # to fix, not something this codepath should silently paper over
  [ ! -f "$WS/.devcontainer/Dockerfile" ]
}

@test "surfaces an existing named sub-config, then still scaffolds the default when none was requested" {
  mkdir -p "$WS/.devcontainer/custom"
  echo '{}' > "$WS/.devcontainer/custom/devcontainer.json"
  run main "$WS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"also has sub-config(s) here: custom"* ]]
  [ -f "$WS/.devcontainer/devcontainer.json" ]
  # the pre-existing sub-config must be untouched, not overwritten by the
  # default-profile scaffold (scaffold_devcontainer skips subdirectories)
  run cat "$WS/.devcontainer/custom/devcontainer.json"
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

# ── --claude (persistent tmux session) ────────────────────────────────────

@test "--claude attaches to a persistent tmux session" {
  run main "$WS" --claude
  [ "$status" -eq 0 ]
  mock_called_with "tmux new-session -A -s claude claude"
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

@test "a project-local git identity overrides the host global default" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  git config --global user.name "Global User"
  git config --global user.email "global@example.com"
  git -C "$WS" init -q
  git -C "$WS" config user.name "Project Bot"
  git -C "$WS" config user.email "bot@example.com"
  run main "$WS"
  [ "$status" -eq 0 ]
  mock_called_with "git config --global user.name Project Bot"
  mock_called_with "git config --global user.email bot@example.com"
  ! mock_called_with "git config --global user.name Global User"
}
