#!/bin/sh
# install.sh — bootstrap installer for dco.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/blakeboswell/dco/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/blakeboswell/dco/main/install.sh | sh -s -- PREFIX=/usr/local
#
# Clones the repo into a temp dir and runs `make install` there, so the
# real install logic lives in exactly one place: the Makefile.
set -e

command -v git  >/dev/null 2>&1 || { echo "install.sh: error: git is required" >&2; exit 1; }
command -v make >/dev/null 2>&1 || { echo "install.sh: error: make is required" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --depth 1 https://github.com/blakeboswell/dco.git "$tmp"
make -C "$tmp" install "$@"
