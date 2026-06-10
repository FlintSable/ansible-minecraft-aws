#!/usr/bin/env bash
# 001_provision.sh - provision AWS resources for ansible-minecraft-aws.
# Idempotent: re-running won't double create.

set -euo pipefail
# shellcheck source=_env.sh
source "$(dirname "$0")/_env.sh"

echo "==> Verifying AWS credentials"
aws sts get-caller-identity >/dev/null || {
  echo "ERROR: AWS credentials missing or expired." >&2
  echo "       Refresh them from Learner Lab > AWS Details > AWS CLI." >&2
  exit 1
}

# --- AMI lookup ---------------------------------------------------------------
echo "==> Looking up latest Ubuntu 22.04 LTS AMI (Canonical, owner 099720109477)"
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
           "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)
echo "    AMI_ID=$AMI_ID  INSTANCE_TYPE=$INSTANCE_TYPE"

# --- SSH key + AWS key pair ---------------------------------------------------
echo "==> Ensuring local SSH key $KEY_FILE exists"
if [[ ! -f "$KEY_FILE" ]]; then
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t rsa -N "" -f "$KEY_FILE" -q
  echo "    generated $KEY_FILE (no passphrase)"
else
  echo "    already exists"
  if [[ ! -f "${KEY_FILE}.pub" ]]; then
    ssh-keygen -y -f "$KEY_FILE" > "${KEY_FILE}.pub"
    echo "    regenerated ${KEY_FILE}.pub from private key"
  fi
fi

echo "==> Ensuring AWS has your public key as '$KEY_NAME'"
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  aws ec2 import-key-pair \
    --key-name "$KEY_NAME" \
    --public-key-material "fileb://${KEY_FILE}.pub" >/dev/null
  echo "    imported ${KEY_FILE}.pub as $KEY_NAME"
else
  echo "    already imported"
fi

# --- Security group -----------------------------------------------------------
echo "==> Ensuring security group '$SG_NAME' exists"
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text)
echo "    using default VPC $VPC_ID"

SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || echo "None")

if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
  SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "ansible-minecraft-aws - CS312 Part 2" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)
  echo "    created $SG_ID"
  # Minecraft port - world-open, required for nmap from anywhere.
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
    --protocol tcp --port "$MC_PORT" --cidr "0.0.0.0/0" >/dev/null
  echo "    authorized Minecraft port $MC_PORT from 0.0.0.0/0"
  # SSH - world-open is acceptable here: key-only auth, ephemeral Lab session,
  # ephemeral SG (deleted at teardown), no data on the host.
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
    --protocol tcp --port 22 --cidr "0.0.0.0/0" >/dev/null
  echo "    authorized SSH/22 from 0.0.0.0/0"
else
  echo "    already exists ($SG_ID)"
fi

# --- Instance -----------------------------------------------------------------
echo "==> Checking for existing minecraft instance"
EXISTING=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=$PROJECT_TAG" \
            "Name=tag:Role,Values=minecraft" \
            "Name=instance-state-name,Values=pending,running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

if [[ -n "$EXISTING" ]]; then
  echo "    found existing instance: $EXISTING (skipping launch)"
  INSTANCE_ID="$EXISTING"
else
  echo "==> Launching $INSTANCE_COUNT minecraft instance"
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --count "$INSTANCE_COUNT" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --iam-instance-profile Name=LabInstanceProfile \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Project,Value=$PROJECT_TAG},{Key=Role,Value=minecraft}]" \
    --query 'Instances[0].InstanceId' \
    --output text)
  echo "    launched $INSTANCE_ID"
fi

echo "==> Waiting for instance to enter 'running' state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
echo "    running."

# --- Public IP ----------------------------------------------------------------
# Auto assigned IPv4 persists for the lifetime of the running instance
# (including across reboot), which is all this project's flows need.
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo
echo "==> Provisioning complete."
echo "    instance:    $INSTANCE_ID"
echo "    public IPv4: $PUBLIC_IP"
echo "    next: ./002_inventory.sh"
