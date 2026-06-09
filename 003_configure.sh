#!/usr/bin/env bash
# 003_configure.sh - run the Ansible playbook on the minecraft host, then nmap-verify.

set -euo pipefail
# shellcheck source=_env.sh
source "$(dirname "$0")/_env.sh"

HOSTS_FILE="hosts.ini"

export ANSIBLE_NOCOLOR=1
export ANSIBLE_HOST_KEY_CHECKING=False

command -v ansible >/dev/null || {
  echo "ERROR: 'ansible' not found. Install with: brew install ansible" >&2
  exit 1
}
command -v nmap >/dev/null || {
  echo "ERROR: 'nmap' not found. Install with: brew install nmap" >&2
  exit 1
}

if [[ ! -f "$HOSTS_FILE" ]]; then
  echo "ERROR: $HOSTS_FILE missing. Run ./002_inventory.sh first." >&2
  exit 1
fi

# Extract the host IP for the SSH wait + nmap verification.
PUBLIC_IP=$(grep -E '^mc1 +ansible_host=' "$HOSTS_FILE" | awk -F= '{print $2}')
if [[ -z "$PUBLIC_IP" ]]; then
  echo "ERROR: couldn't parse public IP from $HOSTS_FILE" >&2
  exit 1
fi

echo "==> Pre-flight: syntax-check playbook"
ansible-playbook --syntax-check -i "$HOSTS_FILE" playbooks/site.yml >/dev/null
echo "    OK"

# Wait until SSH accepts and cloud-init has finished. cloud-init status --wait
# blocks server-side until cloud-init reports done; BatchMode + ConnectTimeout
# keep the probe fast-failing while we loop.
echo "==> Waiting for cloud-init on $PUBLIC_IP (cloud-init may still be initializing)..."
until ssh -o StrictHostKeyChecking=accept-new \
          -o ConnectTimeout=5 \
          -o BatchMode=yes \
          -i "$KEY_FILE" \
          "ubuntu@$PUBLIC_IP" 'cloud-init status --wait >/dev/null 2>&1 || true' >/dev/null 2>&1; do
  printf '.'
  sleep 5
done
echo " ready"

echo "==> Running ansible-playbook"
ansible-playbook -i "$HOSTS_FILE" playbooks/site.yml

echo
echo "==> Verifying Minecraft port with nmap"
nmap -sV -Pn -p "T:$MC_PORT" "$PUBLIC_IP"

echo
echo "==> Configure + verify complete."
echo "    public IPv4: $PUBLIC_IP"
echo "    server:      $PUBLIC_IP:$MC_PORT"
echo "    teardown:    ./088_teardown.sh"
