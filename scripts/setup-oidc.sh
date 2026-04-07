#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------
# Setup OIDC for GitHub Actions → K3s keyless auth
#
# Run this on the K3s master node (master-xeon):
#   curl -fsSL <raw-url> | sudo bash
#   OR
#   sudo bash scripts/setup-oidc.sh
#
# What it does:
#   1. Adds OIDC flags to K3s API server config
#   2. Restarts K3s
#   3. Applies RBAC for GitHub Actions
# -----------------------------------------------------------

K3S_CONFIG="/etc/rancher/k3s/config.yaml"
RBAC_FILE="clusters/master-xeon/rbac-github-actions.yaml"

echo "=== Step 1: Configure K3s API server for GitHub OIDC ==="

# Check if OIDC is already configured
if grep -q "oidc-issuer-url" "$K3S_CONFIG" 2>/dev/null; then
  echo "OIDC flags already present in $K3S_CONFIG. Skipping."
else
  # Backup current config
  cp "$K3S_CONFIG" "${K3S_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

  # Append OIDC flags
  cat >> "$K3S_CONFIG" <<'OIDC'

# GitHub Actions OIDC authentication
kube-apiserver-arg:
  - "--oidc-issuer-url=https://token.actions.githubusercontent.com"
  - "--oidc-client-id=sts.amazonaws.com"
  - "--oidc-username-claim=sub"
  - "--oidc-groups-claim=repository"
OIDC

  echo "OIDC flags appended to $K3S_CONFIG"
fi

echo ""
echo "=== Step 2: Restart K3s ==="
systemctl restart k3s
echo "K3s restarted. Waiting for API server..."
sleep 10

# Verify API server is up
until kubectl get nodes &>/dev/null; do
  echo "Waiting for API server..."
  sleep 5
done
echo "API server is ready."

echo ""
echo "=== Step 3: Apply RBAC ==="
if [[ -f "$RBAC_FILE" ]]; then
  kubectl apply -f "$RBAC_FILE"
  echo "RBAC applied."
else
  echo "RBAC file not found at $RBAC_FILE."
  echo "Run: kubectl apply -f clusters/master-xeon/rbac-github-actions.yaml"
fi

echo ""
echo "=== Done ==="
echo "GitHub Actions from acdgbrasil org can now authenticate via OIDC."
echo "Test with: gh workflow run smoke-test.yml"
