#!/usr/bin/env bash
# 000_sync_lab_creds.sh: sync AWS Learner Lab session credentials to GitHub Secrets.
# Run after pasting fresh creds from Learner Lab > AWS Details > AWS CLI into your shell.

set -euo pipefail

# --- Tool checks --------------------------------------------------------------
command -v gh >/dev/null || {
  echo "ERROR: 'gh' not found. Install with: brew install gh && gh auth login" >&2
  exit 1
}
gh auth status >/dev/null 2>&1 || {
  echo "ERROR: gh not authenticated. Run: gh auth login" >&2
  exit 1
}

# --- Credential env-var presence ----------------------------------------------
: "${AWS_ACCESS_KEY_ID:?ERROR: AWS_ACCESS_KEY_ID not set. Paste creds from Learner Lab into your shell first.}"
: "${AWS_SECRET_ACCESS_KEY:?ERROR: AWS_SECRET_ACCESS_KEY not set.}"
: "${AWS_SESSION_TOKEN:?ERROR: AWS_SESSION_TOKEN not set. Learner Lab requires this.}"

# --- Credential validity ------------------------------------------------------
# Confirm the creds actually work before pushing them. Once they're in GH Secrets,
# wrong values surface as opaque workflow failures rather than a clear error here.
echo "==> Validating credentials with sts get-caller-identity"
aws sts get-caller-identity >/dev/null || {
  echo "ERROR: credentials don't work. Paste fresh ones from Learner Lab." >&2
  exit 1
}

# --- Push to GitHub Secrets ---------------------------------------------------
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
echo "==> Pushing to repo: $REPO"

echo "    AWS_ACCESS_KEY_ID"
gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY_ID" --repo "$REPO"

echo "    AWS_SECRET_ACCESS_KEY"
gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_ACCESS_KEY" --repo "$REPO"

echo "    AWS_SESSION_TOKEN"
gh secret set AWS_SESSION_TOKEN --body "$AWS_SESSION_TOKEN" --repo "$REPO"

echo
echo "==> Done. GitHub Actions can now authenticate as your Lab session."
echo "    Note: these credentials expire ~4 hours after the Lab started."
echo "    Re-run this script after each new Lab session."
