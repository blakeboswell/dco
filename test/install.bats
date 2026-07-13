#!/usr/bin/env bats
# Exercises the real `make install`/`make uninstall` targets against an
# isolated PREFIX under this test's tmpdir — never the real ~/.local, and
# never `make regen-devcontainer`, which mutates this repo's own
# .devcontainer/ in place and has no dest parameter to redirect.

load test_helper

@test "make install places dco, templates, and config under PREFIX" {
  prefix="$BATS_TEST_TMPDIR/prefix"
  run make -C "$REPO_ROOT" install PREFIX="$prefix"
  [ "$status" -eq 0 ]

  [ -x "$prefix/bin/dco" ]
  [ -f "$prefix/share/dco/templates/devcontainer.json" ]
  [ -x "$prefix/share/dco/templates/init-firewall.sh" ]
  [ -f "$prefix/share/dco/config/allowlist.txt" ]

  # the @SHAREDIR@ placeholder must be substituted, not left literal
  run grep -F '@SHAREDIR@' "$prefix/bin/dco"
  [ "$status" -ne 0 ]
  run grep -F "$prefix/share/dco" "$prefix/bin/dco"
  [ "$status" -eq 0 ]
}

@test "installed dco prints usage via --help with no other setup" {
  install_dco
  run "$DCO_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "installed dco scaffolds a project from the installed SHAREDIR" {
  install_dco
  use_mocks
  ws="$(new_workspace)"
  run "$DCO_BIN" "$ws"
  [ "$status" -eq 0 ]
  [ -f "$ws/.devcontainer/devcontainer.json" ]
  [ -f "$ws/.devcontainer/allowlist.txt" ]
}

@test "make uninstall removes the installed binary and sharedir" {
  install_dco
  [ -e "$DCO_BIN" ]
  run make -C "$REPO_ROOT" uninstall PREFIX="$DCO_PREFIX"
  [ "$status" -eq 0 ]
  [ ! -e "$DCO_BIN" ]
  [ ! -d "$DCO_SHAREDIR" ]
}

@test "make uninstall warns but succeeds when nothing is installed" {
  prefix="$BATS_TEST_TMPDIR/never-installed"
  run make -C "$REPO_ROOT" uninstall PREFIX="$prefix"
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: nothing found"* ]]
}
