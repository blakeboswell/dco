# Manual end-to-end runbook: new project walkthrough

This validates the parts of `dco` the automated suite (`make test`) can't
reach: a real Docker build, a real interactive `gh repo create`, a real
browser-based PAT creation flow, and the firewall actually enforcing inside
a live container. Run this yourself from a real terminal on your host, not
from inside a Claude session. It needs:

- Docker running
- `@devcontainers/cli` installed (`npm install -g @devcontainers/cli`)
- `gh` installed and authenticated (`gh auth status`)
- `dco` installed from your current checkout of this repo: run `make install`
  first so you're testing your local changes, not whatever's already on
  `PATH`

This test creates a real GitHub repository and a real fine-grained PAT with
write scopes. Do the cleanup section at the end even if you stop partway
through.

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
cat .devcontainer/autonomous/.env.local   # should have DCO_GITHUB_TOKEN= and DCO_GITHUB_HANDLE=
stat -f '%Lp' .devcontainer/autonomous/.env.local   # macOS (use `stat -c '%a'` on Linux): should print 600
grep .env.local .devcontainer/autonomous/.gitignore
git status   # .env.local must NOT show up as untracked/stageable
```

**Verify launch.** You should see:

```
dco: autonomous mode: firewall enforcing, GH_TOKEN set, PR-only workflow, guardrail hook active — launching with --dangerously-skip-permissions
dco: attaching to tmux session 'claude' (creating it if needed; detach with Ctrl-b d)...
```

...followed by Claude starting up inside the tmux session, unattended (no
permission prompts).

## 4. Verify the firewall from inside the container

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

## 5. Cleanup

Do all of this, even if you stopped partway through step 3 or 4:

```sh
dco --stop                                   # remove the container
gh repo delete <your-handle>/test-dco --yes  # delete the GitHub repo
rm -rf ~/tmp/test-dco                        # remove the local checkout
```

Then revoke the PAT: GitHub → Settings → Developer settings → Personal
access tokens → Fine-grained tokens → find the `dco-autonomous-test-dco`
token → Delete.

Finally, check for leftover Docker volumes (named per-project, so they
survive `dco --stop`):

```sh
docker volume ls | grep test-dco
docker volume rm <name>   # for each one, if you don't want to keep it
```
