#!/usr/bin/env bash
# Deeper test pass: which review event-types are actually blocked, and is the
# job's token scoped to only the triggering PR or repo-wide (any open PR)?
set -euo pipefail

echo "=== TEST 1: gh pr review --comment (own PR, not approve) ==="
gh pr review "$PR_NUMBER" --comment --body "Automated: comment-type review test" \
  && echo "RESULT: comment-type review SUCCEEDED" \
  || echo "RESULT: comment-type review FAILED"

echo "=== TEST 2: gh pr review --request-changes (own PR) ==="
gh pr review "$PR_NUMBER" --request-changes --body "Automated: request-changes review test" \
  && echo "RESULT: request-changes on own PR SUCCEEDED" \
  || echo "RESULT: request-changes on own PR FAILED"

echo "=== TEST 3: gh pr review --request-changes on a DIFFERENT, unrelated PR (#2) ==="
gh pr review 2 --request-changes --body "Automated: cross-PR blast-radius test from PR #$PR_NUMBER's workflow run" \
  && echo "RESULT: cross-PR request-changes SUCCEEDED (repo-wide blast radius confirmed)" \
  || echo "RESULT: cross-PR request-changes FAILED"

echo "=== TEST 4: gh pr comment on the DIFFERENT PR (#2) ==="
gh pr comment 2 --body "Automated: cross-PR comment test from PR #$PR_NUMBER's workflow run" \
  && echo "RESULT: cross-PR comment SUCCEEDED" \
  || echo "RESULT: cross-PR comment FAILED"

echo "=== TEST 5: can the token merge the OTHER PR? (read-only check first) ==="
gh pr view 2 --json mergeable,mergeStateStatus,reviewDecision 2>&1 || true
