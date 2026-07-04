# dco — Dev Container Open

A small wrapper around the [`devcontainer` CLI](https://github.com/devcontainers/cli) for
quickly opening a shell (or Claude Code) in a project's devcontainer, without
remembering `devcontainer up` / `devcontainer exec` invocations by hand.

## Prerequisites

- [Docker](https://www.docker.com/)
- `@devcontainers/cli`: `npm install -g @devcontainers/cli` (needs Node >= 20)

If a project has no `.devcontainer.json` / `.devcontainer/devcontainer.json`,
`dco` scaffolds a default one (Node 20, zsh, Claude Code preinstalled, tmux,
firewall hook disabled by default).

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

```
dco                              # shell in CWD's container
dco ~/projects/trading           # shell in a specific project
dco . gpu-trading                # named sub-config under .devcontainer/<name>/
dco --claude                     # attach/create tmux session running Claude
dco --rebuild --claude           # rebuild the image, then launch Claude
dco --stop ~/projects/trading    # remove that project's container
dco --list                       # show all running devcontainers
```

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

## Shell function

Add to `.zshrc` to `cd` and open in one step:

```sh
cdco() { cd "$1" && dco "${@:2}"; }
```
