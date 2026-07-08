# dco — Dev Container Open

`dco` creates and manages a sandboxed dev container for a project in one command —
scaffolding a sensible default if none exists, keeping your git identity
synced from the host, and treating Claude Code sessions as persistent rather
than one-off. It's built on the
[`devcontainer` CLI](https://github.com/devcontainers/cli).

## Prerequisites

- [Docker](https://www.docker.com/)
- `@devcontainers/cli`: `npm install -g @devcontainers/cli` (needs Node >= 20)

## Install

```sh
git clone https://github.com/blakeboswell/dco.git
cd dco
make install                 # installs to ~/.local/bin and ~/.local/share/dco
```

Override the install location with `make install PREFIX=/usr/local`.
`make uninstall` removes both. See `make help` for all targets.

## Usage

```
dco [path] [sub-config] [flags]
```

| Flag | Effect |
|---|---|
| `-c`, `--claude` | Launch Claude Code in a persistent tmux session (see below) |
| `-r`, `--rebuild` | Force rebuild (removes existing container first) |
| `-s`, `--stop` | Stop and remove the project's container |
| `-l`, `--list` | List all running devcontainers |
| `-h`, `--help` | Show help |

## Detaching and reattaching to Claude

`--claude` runs Claude inside `tmux new-session -A -s claude`, which attaches
to the session if it's already running or creates it otherwise. This means
you can step out and come back later without losing the conversation:

1. `dco --claude` — opens (or creates) the container and attaches to the
   `claude` tmux session.
2. Detach with `Ctrl-b` then `d`. Claude keeps running inside the container.
3. Do whatever you need on the host.
4. `dco --claude` again (same project) — reattaches to the same session,
   scrollback and conversation intact.

This only works while the container itself stays up — don't run `dco --stop`
or restart Docker in between. Plain `dco` shells (without `--claude`) are not
persistent; each invocation opens a fresh `devcontainer exec` session.

## Git identity

Every launch, `dco` reads `git config --global user.name` / `user.email` from
the host and sets the same values inside the container (`git config --global`
there too). No flags, no manual setup per container — it just mirrors
whatever your host is currently configured with. Only these two values are
synced; other git config (aliases, signing, credential helpers) is not.
