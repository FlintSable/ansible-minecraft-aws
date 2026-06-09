#!/usr/bin/env bash
# 000_sync_lab_creds.sh: sync AWS Learner Lab session credentials to GitHub Secrets.
# Reads from ~/.aws/credentials (the [default] profile, or AWS_PROFILE if set).
# Run after refreshing ~/.aws/credentials from Learner Lab > AWS Details > AWS CLI.

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

# --- Read credentials from ~/.aws/credentials ---------------------------------
PROFILE="${AWS_PROFILE:-default}"
AKI=$(aws configure get aws_access_key_id     --profile "$PROFILE" 2>/dev/null || true)
SAK=$(aws configure get aws_secret_access_key --profile "$PROFILE" 2>/dev/null || true)
SST=$(aws configure get aws_session_token     --profile "$PROFILE" 2>/dev/null || true)

[[ -n "$AKI" ]] || { echo "ERROR: aws_access_key_id missing from profile [$PROFILE] in ~/.aws/credentials" >&2; exit 1; }
[[ -n "$SAK" ]] || { echo "ERROR: aws_secret_access_key missing from profile [$PROFILE] in ~/.aws/credentials" >&2; exit 1; }
[[ -n "$SST" ]] || { echo "ERROR: aws_session_token missing from profile [$PROFILE] in ~/.aws/credentials. Lab creds expire roughly every 4 hours; refresh from Learner Lab." >&2; exit 1; }

# --- Credential validity ------------------------------------------------------
# Confirm the creds actually work before pushing them. Once they're in GH Secrets,
# wrong values surface as opaque workflow failures rather than a clear error here.
echo "==> Validating credentials with sts get-caller-identity"
AWS_PROFILE="$PROFILE" aws sts get-caller-identity >/dev/null || {
  echo "ERROR: credentials in profile [$PROFILE] don't work. Refresh ~/.aws/credentials from Learner Lab." >&2
  exit 1
}

# --- Push to GitHub Secrets ---------------------------------------------------
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
echo "==> Pushing to repo: $REPO"

echo "    AWS_ACCESS_KEY_ID"
gh secret set AWS_ACCESS_KEY_ID --body "$AKI" --repo "$REPO"

echo "    AWS_SECRET_ACCESS_KEY"
gh secret set AWS_SECRET_ACCESS_KEY --body "$SAK" --repo "$REPO"

echo "    AWS_SESSION_TOKEN"
gh secret set AWS_SESSION_TOKEN --body "$SST" --repo "$REPO"

echo
echo "==> Done. GitHub Actions can now authenticate as your Lab session."
echo "    Note: these credentials expire ~4 hours after the Lab started."
echo "    Re-run this script after each new Lab session."
