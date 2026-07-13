# dco: Dev Container Open

`dco` creates and manages a sandboxed dev container for a project in one command:
scaffolding a sensible default if none exists, keeping your git identity
synced from the host, and treating Claude Code sessions as persistent rather
than one-off. It's built on the
[`devcontainer` CLI](https://github.com/devcontainers/cli).

## Prerequisites

- [Docker](https://www.docker.com/)
- `@devcontainers/cli`: `npm install -g @devcontainers/cli` (needs Node >= 20)
- [`gh`](https://cli.github.com/) >= 2.29.0, for autonomous mode (`--dsp`) only:
  repo creation, the PAT setup flow, and bootstrapping the `ready`/etc.
  labels all need `gh label`, added in 2.29.0. Distro-packaged `gh` (e.g.
  Ubuntu's apt archive) is often years stale; if `gh label create` errors
  with `unknown command "label"`, switch to
  [GitHub's own apt repo](https://cli.github.com/) rather than trying to
  upgrade the distro package.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/blakeboswell/dco/main/install.sh | sh
```

Installs `dco` to `~/.local/bin` and its templates/config to
`~/.local/share/dco`. Override the location with
`curl ... | sh -s -- PREFIX=/usr/local`.

To uninstall, clone the repo and run `make uninstall` (with the same
`PREFIX` if you overrode it). See `make help` for all targets.

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
| `--dsp` | Launch Claude with `--dangerously-skip-permissions` (implies `--claude`; defaults `--sub-config` to `autonomous`, see below) |
| `--sub-config <name>` | Use `.devcontainer/<name>/devcontainer.json` instead of the default profile |
| `-l`, `--list` | List all running devcontainers |
| `-h`, `--help` | Show help |

`--sub-config <name>` is *not* a separate directory to create alongside your
project: it names an alternate devcontainer config at
`<path>/.devcontainer/<name>/devcontainer.json`, for projects that need more
than one profile (e.g. a default one plus a locked-down `autonomous` one).
If that sub-config doesn't exist yet, `dco` scaffolds it from a shipped
template of the same name (currently just `autonomous`). `--dsp` defaults
`--sub-config` to `autonomous` when you don't pass one explicitly, since
that's the profile with a populated allowlist and the guardrail hook, both
of which `--dsp` requires; pass `--sub-config` yourself to run a different,
custom-scoped autonomous profile instead.

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

## Autonomous mode (`--dsp`)

`dco --dsp` runs Claude unattended: no tool-use prompts at all,
with this repo's GitHub Issues and PRs as its task queue and its way to ask
you questions. Think of it as directing a team of junior engineers rather
than pairing on every line.

`--dsp` starts exactly one session in a persistent tmux session; it doesn't
make anything poll GitHub on a schedule by itself, and a bare
`claude --dangerously-skip-permissions` just opens an interactive session
and waits, since Claude Code doesn't act on `CLAUDE.md` without a first
turn. So `--dsp` sends one itself, as the session's first message,
directing it to `CLAUDE.md`: check whether a recurring schedule already
exists for the project and, if not, set one up itself (using its own
scheduling tooling) before doing anything else, so the issue queue
actually gets checked over time rather than only whenever a human happens
to reopen the session. This only fires on a genuinely fresh session:
reattaching to one that's already running (`dco --dsp` again, or
`dco --sub-config autonomous`) never re-sends it mid-conversation. `dco`
deliberately doesn't implement the *recurring* half of this itself:
Claude Code's own scheduling primitives already handle session resumption
and auth properly, and reimplementing that as a host-side cron job inside
`dco` would just be a less robust version of the same thing.

Running with zero prompts only makes sense alongside a few other things:

1. **A real firewall.** Autonomous mode flips network posture from this
   tool's normal open-by-default to enforced default-deny, using a populated
   allowlist instead of the empty one the default profile ships with. Each
   allowlist domain is resolved (and GitHub's IP ranges fetched) with a
   short retry on failure; a domain that still won't resolve is skipped
   with a warning rather than aborting the whole container, so one flaky
   DNS lookup doesn't take down the entire launch.
2. **A scoped credential.** A fine-grained GitHub token limited to the
   target repo, not your full personal access.
3. **A PR-only workflow.** Claude opens PRs against issues; a human always
   merges. That review step is the main "engineer says so" checkpoint.
4. **A guardrail hook.** Hard-blocks force-push, direct pushes to
   `main`/`master`, PR self-merge, and repo/branch-protection edits, even
   under `--dangerously-skip-permissions` (hooks are a separate enforcement
   layer from the permission system).

Setup:

1. Enable branch protection on the target repo: require PR review, disallow
   force-push. This is the real, server-side backstop; the guardrail hook
   above is a local layer underneath it, not a replacement for it. This one
   step isn't automatable and has to happen on GitHub itself.
2. `dco --dsp`.

Everything else, `dco` handles for you when run from a real terminal:

- If the workspace has no GitHub remote, it offers to run
  `gh repo create --private --source=. --remote=origin --push` using
  whatever `gh` auth is already on your host (a separate credential from the
  token below, so this doesn't widen the container's own access). If a repo
  of that name already exists under your account (e.g. a naming collision
  from a prior attempt), it offers to add that one as `origin` and push to
  it instead of failing outright.
- If `DCO_GITHUB_TOKEN` isn't set, it opens a pre-filled fine-grained token
  creation page (name, description, expiration, and exactly the
  Contents/Issues/Pull-requests-write permissions needed already filled in;
  you still pick the specific repo and click Generate, since a URL alone
  shouldn't be able to grant that), prompts you to paste the result back in,
  and asks for your GitHub handle (used for `@mentions`, defaulting to
  whatever `gh` already knows about you). Both inputs are stripped of
  control characters and ANSI escape sequences before being saved, since a
  terminal that echoes a stray cursor-move code mid-paste can otherwise
  corrupt the saved token into one that fails every API call with an
  "invalid header field value" error, silently.
- Both get saved to a gitignored `.env.local` next to the scaffolded
  profile (`chmod 600`), so this only happens once per project.
- The `ready`/`in-progress`/`in-review`/`blocked` labels the operating
  instructions' task queue depends on get created (or updated, if already
  present) on the repo, every launch. Only issues labeled `ready` are ever
  picked up: filing an issue doesn't queue it up on its own, you also need
  to apply that label yourself once it's vetted.

None of this happens non-interactively: without a terminal to prompt in,
`dco` still just fails fast with instructions, the same as before. You can
also always do either step manually. To set the token yourself:
```sh
export DCO_GITHUB_TOKEN=github_pat_...
export DCO_GITHUB_HANDLE=yourhandle
```

`dco` refuses to launch `--dsp` if the workspace isn't a git repo with a
GitHub remote, if the resolved config's allowlist has no active entries
(the firewall would be a no-op), or if `DCO_GITHUB_TOKEN` isn't set. None of
this is transactional: a repo it creates, a token it saves, or a container
it builds all stay in place even if a later step in the same launch fails,
so retrying after a failure is normally cheap rather than something you
need to clean up first. The one exception is a container that's already
running for the exact same profile: `--dsp` warns and asks before
proceeding, since two live autonomous sessions against the same repo can
duplicate work on the same issue (not a data-loss risk: branches are
independent and the guardrails above hold regardless, just wasted effort
and faster GitHub API rate-limit usage).

The shipped allowlist already covers Node, Python, Rust, Go, apt, and the
common GitHub CDNs that trip up allowlist firewalls (raw file fetches,
tarball downloads, release assets). Review
`.devcontainer/autonomous/allowlist.txt` for anything else your project
needs, and `.devcontainer/autonomous/CLAUDE.md` for the operating
instructions Claude follows: label taxonomy, the PR workflow, and when to
ask versus proceed.

`allowlist.txt` is bind-mounted read-only into the container, so an edit on
the host takes effect immediately, without a rebuild: run
`sudo /usr/local/bin/init-firewall.sh` inside the container to apply it (the
`node` user already has passwordless sudo scoped to exactly that command).
Claude can't edit the allowlist itself (the mount is read-only), so a new
domain always goes through you: it'll ask via a `blocked` issue, and once
you've added and committed the domain, it reloads the firewall itself.

`init-firewall.sh` itself works differently: it's baked into the image at
build time by the shared `Dockerfile` every profile uses (deliberately not
bind-mounted: a container user with write access to it, combined with the
passwordless sudo above, would be a straightforward privilege escalation).
That means there's only ever one copy, `.devcontainer/init-firewall.sh` at
the top level, regardless of sub-config; `dco --regen [path]` refreshes it
for every profile, autonomous included, even though `--regen` otherwise
only touches the top-level `.devcontainer/`.

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

`test/unit.bats` covers `dco.in`'s standalone helper functions (URL/slug
encoding, GitHub remote parsing, template scaffolding) by sourcing the
script directly. `test/cli.bats` drives `main()` end-to-end, including the
`--dsp` guardrails, against fake `docker`/`devcontainer`/`gh` binaries in
`test/mocks/` so nothing touches a real container or GitHub. `test/install.bats`
exercises `make install`/`uninstall` against an isolated temp prefix. None
of the suite touches this repo's own `.devcontainer/`, `~/.local`, or your
real git config.

For changes that touch the interactive/autonomous-mode paths (`gh repo
create`, PAT setup, the live firewall), see
[`docs/e2e-runbook.md`](docs/e2e-runbook.md): a manual walkthrough that
creates a real throwaway GitHub repo and exercises the full `--dsp` setup
flow, since that can't be mocked the way `make test` mocks it.
