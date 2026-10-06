#!/usr/bin/env bash
# Trusted/base-branch version of the "review command" the workflow executes.
# In the real vulnerable workflows, this is a Claude Code project slash
# command (.claude/commands/review-pr-ci.md etc.) instead of a shell script,
# but it is read from the same checked-out working directory either way.
set -euo pipefail
echo "Legitimate review: no issues found for PR #$PR_NUMBER."
