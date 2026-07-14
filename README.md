# dco: Dev Container Open

`dco` creates and manages a sandboxed dev container for a project in one command:
scaffolding a sensible default if none exists, keeping your git identity
synced from the host, and treating Claude Code sessions as persistent rather
than one-off. It's built on the
[`devcontainer` CLI](https://github.com/devcontainers/cli).

## Prerequisites

- [Docker](https://www.docker.com/)
- `@devcontainers/cli`: `npm install -g @devcontainers/cli` (needs Node >= 20)

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/blakeboswell/dco/main/install.sh | sh
```

To uninstall:

```sh
curl -fsSL https://raw.githubusercontent.com/blakeboswell/dco/main/uninstall.sh | sh
```

To customize the install (location, etc.), clone the repo and see the
Makefile (`make help` for all targets).

## Usage

```
dco [path] [flags]
```

`path` is the project directory (default: current directory).

| Flag | Effect |
|---|---|
| `-c`, `--claude` | Launch Claude Code in the project's devcontainer, in a persistent tmux session (see below) |
| `-r`, `--rebuild` | Force rebuild (removes existing container first) |
| `-s`, `--stop` | Stop and remove the project's container |
| `--purge` | Like `--stop`, but also deletes its volumes (bash history, Claude's memory). Irreversible, always confirms first |
| `-g`, `--regen` | Refresh a project's `.devcontainer/` from the latest templates |
| `--sub-config <name>` | Use `.devcontainer/<name>/devcontainer.json` instead of the default profile. Not scaffolded for you: commit that file yourself first |
| `-l`, `--list` | List all running devcontainers |
| `-h`, `--help` | Show help |

## Detaching and reattaching to Claude

`--claude` runs Claude inside `tmux new-session -A -s claude`, which attaches
to the session if it's already running or creates it otherwise. This means
you can step out and come back later without losing the conversation:

1. `dco --claude`: opens (or creates) the container and attaches to the
   `claude` tmux session.
2. Detach with `Ctrl-b` then `d`. Claude keeps running inside the container.
3. Do whatever you need on the host.
4. `dco --claude` again (same project): reattaches to the same session,
   scrollback and conversation intact.

This only works while the container itself stays up. Don't run `dco --stop`
or restart Docker in between. Plain `dco` shells (without `--claude`) are not
persistent; each invocation opens a fresh `devcontainer exec` session.

## Claude's memory across container rebuilds

Separately from the tmux session above, `~/.claude` inside the container
(Claude's config, memory, and session history) lives on a named Docker
volume, keyed to the project's path and sub-config rather than the container
itself. That means it survives `dco --stop`, `dco --rebuild`, and even
deleting and recreating the container from scratch. Only removing the Docker
volume itself would lose it: `dco --purge [path]` does exactly that,
deliberately, with a confirmation prompt first.

This only applies to projects whose `.devcontainer/` already has the
`mounts` entries from the current `templates/devcontainer.json`. If a
project's `.devcontainer/` was scaffolded before this existed, or was
hand-edited, refresh it with `dco --regen [path]` and then `dco --rebuild`.

## Network firewall

Every profile ships with an optional default-deny firewall: populate
`.devcontainer/allowlist.txt` with the domains it needs, then
`dco --rebuild` (empty, the default, means fully open). `make
check-domains` verifies every entry actually resolves.

## Git identity

Every launch, `dco` reads `user.name`/`user.email` from the host (via git's
own config resolution: the project's local config if set, else your global
one) and sets those values as the container's global git config. Defaults
to your host identity with no setup; override it per-project the normal
git way: `git -C /path/to/project config user.name "..."` on the host,
no dco-specific mechanism needed. Only these two values are synced; other
git config (aliases, signing, credential helpers) is not.

