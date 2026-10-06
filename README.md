# PoC: fork-controlled file executes with privileged CI token via `workflow_dispatch` + `refs/pull/<N>/head` checkout

Minimal, self-contained reproduction of the pattern found in
`anthropics/claude-cookbooks` (`.github/workflows/claude-pr-review.yml`,
`claude-model-check.yml`, `claude-link-review.yml`). This repo does not
depend on Anthropic's infrastructure, WIF credentials, or the real
`claude-code-action` — it isolates the exploitable *mechanism* so it can be
demonstrated without touching Anthropic's production CI.

## The pattern (identical in all 3 real files)

```yaml
on:
  pull_request:
    types: [opened, synchronize]
  workflow_dispatch:
    inputs:
      pr_number: { required: true, type: number }

permissions:
  pull-requests: write   # a real, usable token

jobs:
  review:
    if: github.event_name == 'workflow_dispatch' || github.event.pull_request.head.repo.full_name == github.repository
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event_name == 'workflow_dispatch' && format('refs/pull/{0}/head', inputs.pr_number) || '' }}
      - run: <execute a repo-local file from the checkout>   # real repo: Claude slash command; here: bash script
```

The automatic trigger correctly skips fork PRs. The manual
`workflow_dispatch` escape hatch — meant for a maintainer to say "also
review this external contribution" — does not: it checks out the **fork's
HEAD** and then executes a file from that same checkout, with a token that
has write access.

## Steps to reproduce

1. Base branch (`main`) carries `.github/workflows/dispatch-review.yml` and
   a trusted `.github/commands/review.sh` that just prints a message.
2. Attacker branch/fork (`attacker-pr`) opens a PR that **only** changes
   `.github/commands/review.sh`, replacing it with a version that calls
   `gh pr review --approve` on its own PR number, using
   `secrets.GITHUB_TOKEN` — the token the *base* workflow grants, not
   anything the attacker provides.
3. A maintainer, trusting this is "just the review workflow," manually
   dispatches `Dispatch Review` against that PR's number (Actions tab →
   Run workflow → pr_number = N). This is the exact, intended, documented
   use of the escape hatch — no social engineering, no unusual trigger.
4. Checkout step pulls `refs/pull/N/head` → the attacker's `review.sh`.
5. The job runs the attacker's script with the real, write-scoped
   `GITHUB_TOKEN` → the PR is auto-approved by the bot identity, with zero
   legitimate review having occurred.

## Why this matters for claude-cookbooks specifically

Same checkout pattern, same `workflow_dispatch` design, same missing
fork-content isolation — except the "file executed from the checkout" is a
Claude Code project slash command (`.claude/commands/review-pr-ci.md`,
`model-check.md`, `link-review.md`, all confirmed present in the real repo)
invoked with a real WIF-issued Claude credential, `pull-requests: write`,
and (in `claude-model-check.yml` / `claude-link-review.yml`) `WebFetch` +
`Bash(echo:*)` in the allowed tool list — a workable secret-exfiltration
primitive, not just an auto-approve. `claude-pr-review.yml`'s allowed tools
include `Bash(gh pr review:*)` directly, so the auto-approve shown in this
PoC maps onto it with no substitution needed at all.

Anthropic's own `claude-code-action` repo does this correctly elsewhere:
its PR-review workflow skips fork PRs entirely with no manual escape hatch,
and its issue-triage workflow (which does need to run on arbitrary-user
content) checks out the base ref, runs on an egress-firewalled runner, and
uses `--permission-mode auto`. `claude-cookbooks` has none of these
mitigations on its `workflow_dispatch` path.
