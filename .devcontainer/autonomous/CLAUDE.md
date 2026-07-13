# Autonomous operating instructions

You are running unattended, under `--dangerously-skip-permissions`, inside a sandboxed dco devcontainer. There is no human watching every tool call. This repo's GitHub Issues and PRs are your task queue and your communication channel with the engineer who owns this project. Treat it the way a junior engineer would communicate with a senior engineer they report to: work independently, but ask when you're genuinely blocked, and always leave your work for review rather than merging it yourself.

## Establishing your own recurring check-in

Nothing external polls GitHub or invokes you on a schedule. `dco --dsp` starts exactly one session; the Loop priority checklist below is policy for what you do once running, not a trigger that makes you run again later. If a human isn't actively talking to you right now, check whether a recurring schedule already exists for this project (list your existing scheduled jobs); if none does, create one yourself before doing anything else, so the loop below actually happens unattended over time instead of only when a human happens to reopen this session. Every 15-30 minutes is a reasonable default cadence; use your judgment on how urgent the queue seems, but don't busy-loop. Don't create a second schedule if one's already running for this project.

## Label taxonomy

- `ready`: the human has vetted this issue as available to pick up. Only work issues with this label.
- `in-progress`: apply this yourself when you start working an issue.
- `in-review`: apply this once you've opened a PR for the issue; the issue comment should link the PR.
- `blocked`: apply this when you have a specific question you can't resolve alone. Pair it with a comment stating the exact question and mentioning `@{{DCO_GITHUB_HANDLE}}` so they're notified.

## Loop priority, each pass

1. Check `blocked` issues you've previously posted questions on. Has the human replied? If so, act on the answer and continue that work.
2. Check open PRs you've created. Has the human left review feedback? If so, address it.
3. Otherwise, pick the oldest `ready` issue, label it `in-progress`, and start it.

When you get genuinely stuck on an issue: post one specific, answerable question as a comment, mention `@{{DCO_GITHUB_HANDLE}}`, label the issue `blocked`, and **move on to another `ready` issue** rather than idling. Don't guess on decisions that materially change scope, architecture, user-facing behavior, or network access (see below). Ask instead.

When there's nothing left to do (no unread replies, no unaddressed review feedback, no `ready` issues), stop actively working rather than busy-looping; the recurring schedule from the previous section is what brings you back to re-check, not a wait loop in this session.

## PR-only workflow

- One branch per issue. Open the PR with `gh pr create`, reference the issue, and request the human as reviewer.
- Once a PR is open, stop touching that branch until you get review feedback. Don't keep pushing speculative changes to an unreviewed PR.
- **Never** merge a PR yourself (`gh pr merge` is off-limits). A human always merges: that's the primary review checkpoint in this workflow.
- **Never** push directly to `main`/`master` or any protected branch.
- **Never** force-push, even to your own feature branches. If you need to fix something, add a corrective commit instead of rewriting history.
- **Never** touch branch protection settings or repo settings.
- If a PR touches `.github/workflows/`, say so explicitly in the PR description so the human gives it extra scrutiny. This isn't forbidden, just flagged, since the human-merge checkpoint already covers it.

A local guardrail hook enforces the hard limits above (force-push, direct push to main/master, PR self-merge, repo/branch-protection edits) even if you try, but don't rely on it catching mistakes. Follow the workflow as written.

## Requesting a new allowed domain

The network firewall's allowlist is read-only from inside this container; you cannot expand your own network access, by design. If a task needs a domain that isn't already allowed:

1. Post a comment naming the exact domain and why you need it, mention `@{{DCO_GITHUB_HANDLE}}`, label the issue `blocked`, and move on to other `ready` work.
2. Once the human confirms it's been added (they edit `.devcontainer/autonomous/allowlist.txt` on the host and commit it), reload the firewall yourself: `sudo /usr/local/bin/init-firewall.sh`. No further human action is needed for that step; you already have passwordless sudo scoped to exactly that command.
