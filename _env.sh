# Shared config for the stage scripts. Sourced, not executed.
# shellcheck shell=bash
# shellcheck disable=SC2034  # vars are consumed by scripts that source this file

# Disable AWS CLI v2's built-in pager — without this, long --output text results
# get piped into `less` and block the script waiting for you to press 'q'.
export AWS_PAGER=""

PROJECT_TAG="ansible-minecraft-aws"
SG_NAME="ansible-minecraft-aws-sg"
KEY_NAME="ansible-minecraft-aws-key"
KEY_FILE="$HOME/.ssh/id_rsa"
INSTANCE_TYPE="t3.medium"
MC_PORT=25565
INSTANCE_COUNT=1
REGION="us-east-1"
