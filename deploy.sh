#!/usr/bin/env bash
# deploy.sh: provision, inventory, configure in one command.
# Same script runs from your laptop and from GitHub Actions.

set -euo pipefail
cd "$(dirname "$0")"

./001_provision.sh
./002_inventory.sh
./003_configure.sh
