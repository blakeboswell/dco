# Manual end-to-end runbook: new project walkthrough

This validates the parts of `dco` the automated suite (`make test`) can't
reach: a real Docker build, a real interactive `gh repo create`, a real
browser-based PAT creation flow, the firewall actually enforcing inside a
live container, and the autonomous loop actually picking up a real issue.
Run this yourself from a real terminal on your host, not from inside a
Claude session. It needs:

- Docker running
- `@devcontainers/cli` installed (`npm install -g @devcontainers/cli`)
- `gh` >= 2.29.0, installed and authenticated (`gh auth status`). Distro-
  packaged `gh` (e.g. Ubuntu's apt archive) is often years stale and lacks
  the `label` subcommand autonomous mode depends on; if `gh --version` is
  old, switch to [GitHub's own apt repo](https://cli.github.com/) first.
- `dco` installed from your current checkout of this repo: run `make install`
  first so you're testing your local changes, not whatever's already on
  `PATH`

This test creates a real GitHub repository and a real fine-grained PAT with
write scopes. Do the cleanup section at the end even if you stop partway
through.

`e2e-runbook.sh`, alongside this file, automates most of the steps below
as resumable subcommands (`setup`, `file-issue`, `check`,
`verify-firewall`, `cleanup`). Each checks current state before acting,
so re-running after a failure resumes rather than repeating already-done
work. The genuinely interactive parts (confirming repo creation, pasting
a PAT) aren't automated, since they're `dco --dsp`'s own prompts, not
something that should be skipped. This file is still the reference for
what to expect at each step; run `./e2e-runbook.sh --help` for the
script's usage.

## 1. Basic scaffolding (no GitHub, no autonomous mode)

Confirms the plain first-run path still works before layering on
`--dsp`.

```sh
mkdir -p ~/tmp/test-dco && cd ~/tmp/test-dco
dco
```

Expect:

- `dco: no devcontainer.json found — creating default .devcontainer in ...`
- `dco: created .../devcontainer.json (Claude Code Sandbox)`
- a container build, then a shell prompt inside `/workspace`

Inside the container, confirm your git identity made it in:

```sh
git config --global user.name
git config --global user.email
```

Both should match what `git config --global user.name`/`user.email` print
on your host. Exit the shell, then from the host:

```sh
dco --stop
```

Expect `dco: removing container for ...` / `dco: done.`. Leave
`~/tmp/test-dco/.devcontainer` in place; step 2 reuses it.

## 2. Git init and GitHub repo creation

```sh
cd ~/tmp/test-dco
git init
echo "# test-dco" > README.md
git add README.md
git commit -m "initial commit"
```

Confirm there's no remote yet: `git remote -v` should print nothing.

## 3. Autonomous mode setup (`--dsp`)

```sh
dco --dsp
```

`--dsp` defaults `--sub-config` to `autonomous` when you don't pass one
explicitly, so this scaffolds and uses `./.devcontainer/autonomous/`, a
second, locked-down devcontainer profile alongside whatever's already at
`./.devcontainer/` from step 1 (they're independent: `autonomous` gets its
own volumes, its own `.env.local`, its own allowlist). See the README's
Usage section for the general `--sub-config` explanation, including how to
point `--dsp` at a different, custom-scoped profile with
`dco --dsp --sub-config <name>`.

Walk through each prompt as it appears:

**No GitHub remote.** You should see:

```
dco: no GitHub remote found for /path/to/test-dco.
dco: create a private GitHub repo 'test-dco' and push? [gh repo create test-dco --private --source="..." --remote=origin --push] [y/N]
```

Answer `y`. Confirm it prints `dco: created and pushed: test-dco` and that
`gh repo view` (or the GitHub UI) shows the new private repo with your
initial commit pushed.

(If a repo named `test-dco` already exists under your account, e.g. a
prior test you didn't clean up, you'd see a different prompt offering to
add it as `origin` and push instead of creating a duplicate. Shouldn't
come up this time if you deleted the old one, but if it does, that's the
`ensure_github_remote` resumability path working as intended, not a bug.)

**Token setup.** Since there's no `DCO_GITHUB_TOKEN` yet, you should see:

```
dco: DCO_GITHUB_TOKEN is not set. Let's set one up.
dco: opening a pre-filled token-creation page (pick just this repo, then Generate token):
dco:   https://github.com/settings/personal-access-tokens/new?...
```

A browser tab should open (or, if there's no `open`/`xdg-open` on your
host, copy the printed URL manually). On that page:

- Confirm the name, description, and 90-day expiration are pre-filled
- Confirm `Contents`, `Issues`, and `Pull requests` are pre-set to
  read/write
- Under "Repository access," select **Only select repositories** and pick
  the `test-dco` repo you just created
- Click **Generate token**, copy it

Back in the terminal:

```
dco: paste the generated token here (input hidden):
```

Paste it (it won't echo) and press enter. Then:

```
dco: your GitHub handle for @mentions [suggested-handle]:
```

Press enter to accept the suggestion, or type your own.

**Verify the saved credentials:**

```sh
cat -A .devcontainer/autonomous/.env.local   # cat -A so a corrupted paste (stray control chars) is visible, not just a clean-looking string
stat -f '%Lp' .devcontainer/autonomous/.env.local   # macOS (use `stat -c '%a'` on Linux): should print 600
grep .env.local .devcontainer/autonomous/.gitignore
git status   # .env.local must NOT show up as untracked/stageable
```

**Verify the label taxonomy got bootstrapped.** Every `--dsp` launch
creates/updates these on the repo, not just on first creation:

```sh
gh label list --repo <your-handle>/test-dco
```

Expect `ready`, `in-progress`, `in-review`, and `blocked` to all be
present, in addition to GitHub's defaults.

**Verify launch.** You should see:

```
dco: autonomous mode: firewall enforcing, GH_TOKEN set, PR-only workflow, guardrail hook active — launching with --dangerously-skip-permissions and an initial bootstrap prompt
dco: attaching to tmux session 'claude' (creating it if needed; detach with Ctrl-b d)...
```

...and then Claude should already be responding to its bootstrap prompt
(checking for/setting up a recurring schedule, then starting the
loop-priority checklist) rather than sitting at an idle prompt waiting for
input. If you land in a blank prompt instead, the bootstrap-prompt
mechanism didn't fire: check you're on the latest `dco` (reinstall) and
that this really was a fresh `tmux new-session`, not a reattach to one
already running (`-A` skips the trailing command on reattach).

## 4. Validate the actual autonomous pickup

This is the thing all the plumbing above exists for. Worth actually
confirming it end-to-end rather than assuming it works because the setup
did. From the host, file a real issue and label it:

```sh
gh issue create --repo <your-handle>/test-dco --title "Hello world" --body "Add a hello.txt file to the repo root containing the text 'hello world'."
gh issue edit <issue-number> --repo <your-handle>/test-dco --add-label ready
```

Detach from (don't stop) the container (`Ctrl-b` then `d` if you're
attached), and watch for activity:

```sh
gh issue view <issue-number> --repo <your-handle>/test-dco --json labels,comments
gh pr list --repo <your-handle>/test-dco
```

There's no fixed polling interval. CLAUDE.md leaves the cadence to the
agent's own judgment (a reasonable default is 15-30 minutes), so don't
expect this instantly. What to actually check if it's been a while with no
movement:

- Is a container still running for this profile? `dco --list`
- Is Claude actually alive in it, not crashed/idle? `dco --sub-config autonomous` then `tmux attach -t claude`
- Does it have working GitHub access? From inside: `gh issue list --repo <your-handle>/test-dco`

Once it picks the issue up, expect: the issue gets labeled `in-progress`,
then a PR appears referencing it (`in-review` on the issue), requesting
you as reviewer. Confirm the PR only touches what the issue asked for, and
that merging is left to you: `gh pr merge` should never have been called
by the agent.

## 5. Verify the firewall from inside the container

Detach (`Ctrl-b` then `d`), then get a plain shell in the same container:

```sh
dco --sub-config autonomous
```

From inside:

```sh
curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 https://example.com || echo "blocked (expected)"
gh issue list   # should succeed: GitHub's API access is handled separately from the static allowlist
```

The first command should fail or time out (`example.com` isn't on the
allowlist: default-deny is working). The second should succeed, confirming
the token and network path to GitHub both work.

If you need to add a domain, edit
`.devcontainer/autonomous/allowlist.txt` on the host (it's bind-mounted
read-only into the container) and reload from inside the container:

```sh
sudo /usr/local/bin/init-firewall.sh
```

A domain that fails to resolve is now retried a few times, then skipped
with a `WARNING:` (not fatal) rather than aborting the whole firewall
setup: if you see one of those for a non-critical domain, that's expected
resilience, not a bug to chase.

## 6. Cleanup

Do all of this, even if you stopped partway through an earlier step:

```sh
dco --purge          # stops the container and deletes its volumes (bash history, Claude memory) -- confirms before doing either
gh repo delete <your-handle>/test-dco --yes
rm -rf ~/tmp/test-dco
```

Then revoke the PAT: GitHub → Settings → Developer settings → Personal
access tokens → Fine-grained tokens → find the `dco-autonomous-test-dco`
token → Delete.
