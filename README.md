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

## Actual results (2026-10-06, run against a live repo: github.com/mrityunjayk-hash/poc-ci-fork-checkout-mechanism)

- **Run 1** — payload tried `gh pr review "$PR_NUMBER" --approve`. **Failed**:
  `GraphQL: GitHub Actions is not permitted to approve pull requests.` This
  is a GitHub platform-level restriction on the `addPullRequestReview`
  mutation specifically, independent of the `pull-requests: write`
  permission granted. **This retracts the "auto-approve via `gh pr
  review --approve`" sub-claim** — it does not work via `GITHUB_TOKEN`,
  on this repo or on `claude-cookbooks`' real `claude-pr-review.yml` (same
  mechanism, same token type). Documented here rather than silently
  dropped, since the program's rules require validated findings only.
- **Run 2** — payload switched to the two primitives a GitHub-side
  approval block does **not** cover:
  1. `gh pr comment` (not `gh pr review`) — **succeeded**. Posted
     [a fabricated "APPROVE, looks good to merge" comment](https://github.com/mrityunjayk-hash/poc-ci-fork-checkout-mechanism/pull/1#issuecomment-6014515528)
     authored by `github-actions[bot]` — the repo's real bot identity —
     entirely from attacker-controlled script content.
  2. Outbound POST of a SHA-256 hash of the real job token (not the raw
     secret) to an external endpoint I control — **succeeded**, payload
     received: `{"poc":"ci-fork-checkout-mechanism","token_sha256":"8136...0f959","repo":"mrityunjayk-hash/poc-ci-fork-checkout-mechanism","pr":"1"}`.
     Proves the secret-exfiltration primitive (maps to `WebFetch` +
     `Bash(echo:*)` in `claude-model-check.yml` / `claude-link-review.yml`)
     is real and not blocked by anything GitHub enforces platform-side.

**Net assessment:** the "attacker auto-approves their own PR" headline claim
does not hold (GitHub blocks it unconditionally). The underlying mechanism —
fork-controlled file executes with a privileged CI token because
`workflow_dispatch` checks out `refs/pull/<N>/head` — is real and
demonstrated, with concrete impact via (a) a misleading bot-authored PR
comment that could social-engineer a human reviewer into merging, and
(b) exfiltration of whatever secret the job holds (the real repo's case:
a live WIF-issued Claude API credential plus `GITHUB_TOKEN`), not merely a
theoretical one.

## Run 3 — deeper pass: review-type variants + cross-PR blast radius (2026-10-06)

Only `--approve` is blocked by GitHub's platform restriction. Tested the
rest of the review API, plus whether the token is scoped to only the
triggering PR:

- `gh pr review <own PR> --comment` — **succeeded**
- `gh pr review <own PR> --request-changes` — **succeeded**
- `gh pr review <a second, completely unrelated PR, #2> --request-changes` —
  **succeeded**. A second "victim" PR (#2, an innocuous unrelated change,
  opened from a separate branch) was created specifically to test this. The
  attacker payload, running because of PR #1's own dispatch, reached out and
  posted a `CHANGES_REQUESTED` review on PR #2 — confirmed via
  `gh pr view 2 --json reviewDecision` returning
  `"reviewDecision":"CHANGES_REQUESTED"` afterward.
- `gh pr comment <PR #2>` — **succeeded**, authored by `github-actions[bot]`:
  https://github.com/mrityunjayk-hash/poc-ci-fork-checkout-mechanism/pull/2#issuecomment-6014698521

**This matters more than the original framing.** The job's `GITHUB_TOKEN` is
scoped to the whole repository, not to the PR that triggered the run. An
attacker doesn't need their own malicious PR to be merged to cause harm —
having it merely *reviewed* (the normal, intended maintainer action) is
enough to let their payload reach out and attack **any other open PR in the
repository**, blocking a legitimate contributor's unrelated work from
merging via a fake "changes requested" from the project's own trusted bot
identity. That's a repo-wide integrity/availability hit on the contribution
pipeline, not a self-contained one, and it doesn't rely on fooling a human
with a fake "LGTM" — it's a direct write-capability abuse that works
regardless of whether anyone reads the comment.
