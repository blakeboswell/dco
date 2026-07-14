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
| `-c`, `--claude` | Launch Claude Code in a persistent tmux session (see below) |
| `-r`, `--rebuild` | Force rebuild (removes existing container first) |
| `-s`, `--stop` | Stop and remove the project's container |
| `--purge` | Like `--stop`, but also deletes its volumes (bash history, Claude's memory). Irreversible, always confirms first |
| `-g`, `--regen` | Refresh a project's `.devcontainer/` from the latest templates |
| `--sub-config <name>` | Use `.devcontainer/<name>/devcontainer.json` instead of the default profile |
| `-l`, `--list` | List all running devcontainers |
| `-h`, `--help` | Show help |

`--sub-config <name>` is *not* a separate directory to create alongside your
project: it names an alternate devcontainer config at
`<path>/.devcontainer/<name>/devcontainer.json`, for projects that need more
than one profile (e.g. a default one plus a GPU-enabled one). `dco` ships no
named profiles of its own to scaffold one from — commit your own
`.devcontainer/<name>/devcontainer.json` first, then point `--sub-config`
at it. It can share the top-level `Dockerfile` the way the default profile's
own config does (`"dockerfile": "../Dockerfile"`), in which case `dco`
scaffolds those shared top-level files too if they don't exist yet.

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

Every profile ships with an optional default-deny network firewall:
`init-firewall.sh` runs as a `postStartCommand` and, if the resolved
config's `allowlist.txt` has any active (non-comment, non-blank) entries,
locks outbound network access down to just those domains plus GitHub's own
IP ranges (always allowed, for git/`gh`). An empty allowlist — what the
default profile ships with — makes it a complete no-op, so `dco` is
open-by-default until you opt in.

To enable it for a project: add domains to `.devcontainer/allowlist.txt`
(or `config/allowlist.txt` before `make install`, to change the default for
every new project) and `dco --rebuild` — `allowlist.txt` is baked into the
image at build time, not bind-mounted, so a plain edit needs a rebuild to
take effect. `make check-domains` resolves every entry over a real DNS
query, worth running after adding one: a domain that looks right but
doesn't actually resolve is otherwise only discoverable as an opaque
firewall failure at container start. A domain that still won't resolve
after a few retries is skipped with a warning rather than aborting the
whole container, so one flaky lookup doesn't take down the entire launch.

`init-firewall.sh` itself is deliberately not bind-mounted: a container
user with write access to it, combined with the passwordless `sudo`
`postStartCommand` needs to run it, would be a straightforward privilege
escalation. That means there's only ever one copy,
`.devcontainer/init-firewall.sh` at the top level, shared by every
sub-config regardless of which one's active; `dco --regen [path]`
refreshes it, even though `--regen` otherwise only touches the top-level
`.devcontainer/`.

## Git identity

Every launch, `dco` reads `git config --global user.name` / `user.email` from
the host and sets the same values inside the container (`git config --global`
there too). No flags, no manual setup per container: it just mirrors
whatever your host is currently configured with. Only these two values are
synced; other git config (aliases, signing, credential helpers) is not.

## Development

Tests use [bats-core](https://github.com/bats-core/bats-core):

```sh
npm install -g bats
make test
```

`test/unit.bats` covers `dco.in`'s standalone helper functions (slug
encoding, template scaffolding) by sourcing the script directly.
`test/cli.bats` drives `main()` end-to-end against fake `docker`/
`devcontainer` binaries in `test/mocks/` so nothing touches a real
container. `test/install.bats` exercises `make install`/`uninstall`
against an isolated temp prefix. None of the suite touches this repo's own
`.devcontainer/`, `~/.local`, or your real git config.

Because `devcontainer`/`docker` are mocked, `make test` verifies `dco`
calls the right commands, but not that the resulting file layout would
actually build: a `devcontainer.json` pointing `"dockerfile"` at a file
that doesn't exist in the scaffolded tree slips straight through mocks
that never read a Dockerfile. `test/unit.bats` also statically checks that
the default profile's `dockerfile` reference resolves to a real file,
both from the source templates and after a fresh scaffold, to catch that
class of bug in milliseconds instead of a multi-minute real Docker cycle.

`make check-domains` resolves every domain in `config/allowlist.txt` over
a real DNS query. Not part of `make test` since it needs actual network
access; run it after adding or changing anything in that file. A domain
that looks right but returns NXDOMAIN is otherwise only discoverable as an
opaque firewall failure at container start.
