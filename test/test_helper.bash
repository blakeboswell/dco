# shared setup for the bats suite — load with `load test_helper` at the top
# of each .bats file (bats resolves that relative to the .bats file's dir)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DCO_SRC="$REPO_ROOT/dco.in"
MOCKS_DIR="$REPO_ROOT/test/mocks"

# Sources dco.in's function definitions into the current shell without
# running main() (the sourcing guard at the bottom of dco.in handles that),
# then points SHAREDIR at the repo root itself — which already has the
# templates/ and config/ layout `make install` would otherwise copy into a
# real SHAREDIR, so scaffold_* functions work unmodified against the repo.
#
# `local -` saves/restores the shell's option state (set -e/-u/pipefail) for
# the lifetime of this function, so dco.in's top-level `set -euo pipefail`
# doesn't leak into the rest of the test process. main() re-asserts strict
# mode itself on entry, so calling `main` after source_dco still runs with
# the same guarantees it has for real.
source_dco() {
  local -
  # shellcheck disable=SC1090
  source "$DCO_SRC"
  SHAREDIR="$REPO_ROOT"
}

# Builds a real installed copy via the Makefile into an isolated prefix
# under this test's tmpdir, so CLI-level tests can exercise the actual
# install path (sed substitution, permissions, file layout) rather than the
# raw script. Sets DCO_BIN / DCO_SHAREDIR / DCO_PREFIX.
install_dco() {
  DCO_PREFIX="$BATS_TEST_TMPDIR/prefix"
  make -C "$REPO_ROOT" install PREFIX="$DCO_PREFIX" >/dev/null
  DCO_BIN="$DCO_PREFIX/bin/dco"
  DCO_SHAREDIR="$DCO_PREFIX/share/dco"
}

# Prepends the fake docker/devcontainer onto PATH and points them at a
# fresh per-test log file, so tests can assert on what dco *would* have run
# without touching real Docker.
use_mocks() {
  MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
  : > "$MOCK_LOG"
  export MOCK_LOG
  PATH="$MOCKS_DIR:$PATH"
}

mock_called_with() {
  grep -qF -- "$1" "$MOCK_LOG"
}

# A throwaway directory tests can treat as a project workspace, isolated
# per-test by bats (BATS_TEST_TMPDIR is unique per test).
new_workspace() {
  local dir="$BATS_TEST_TMPDIR/workspace"
  mkdir -p "$dir"
  printf '%s' "$dir"
}
