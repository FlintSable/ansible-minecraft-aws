#!/usr/bin/env bash
# 088_teardown.sh - release all AWS resources created by 001_provision.sh.

set -euo pipefail
# shellcheck source=_env.sh
source "$(dirname "$0")/_env.sh"

echo "==> Verifying AWS credentials"
aws sts get-caller-identity >/dev/null || {
  echo "ERROR: AWS credentials missing or expired. Refresh from Learner Lab." >&2
  exit 1
}

echo "==> Terminating instances tagged Project=$PROJECT_TAG, Role=minecraft"
IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=$PROJECT_TAG" \
            "Name=tag:Role,Values=minecraft" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

if [[ -n "$IDS" ]]; then
  # shellcheck disable=SC2086  # intentional word-splitting on multiple IDs
  aws ec2 terminate-instances --instance-ids $IDS >/dev/null
  echo "    terminate requested: $IDS"
  # Wait before SG delete - otherwise the SG is still in use by the dying ENI
  # and AWS returns DependencyViolation.
  echo "==> Waiting for instances to terminate..."
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --instance-ids $IDS
  echo "    terminated."
else
  echo "    no matching instances."
fi

echo "==> Deleting security group '$SG_NAME'"
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || echo "None")

if [[ "$SG_ID" != "None" && -n "$SG_ID" ]]; then
  aws ec2 delete-security-group --group-id "$SG_ID"
  echo "    deleted $SG_ID"
else
  echo "    not found."
fi

echo "==> Deleting AWS key pair '$KEY_NAME' (local $KEY_FILE preserved)"
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  aws ec2 delete-key-pair --key-name "$KEY_NAME"
  echo "    deleted from AWS."
else
  echo "    not found."
fi

echo
echo "==> Teardown complete."
