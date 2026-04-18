#!/usr/bin/env bash
# Idempotent Terraform deploy for OpenStack.
# Detects existing resources and imports them into state before applying.
#
# Usage:
#   source setup_env.sh [clouds.yaml] [cloud-name]
#   bash deploy.sh [terraform.tfvars]

set -euo pipefail

TFVARS="${1:-terraform.tfvars}"

if [[ ! -f "${TFVARS}" ]]; then
  echo "ERROR: ${TFVARS} not found"
  exit 1
fi

if [[ -z "${OS_AUTH_URL:-}" ]]; then
  echo "ERROR: OpenStack environment not set. Run: source setup_env.sh first."
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse tfvars values we need for lookups
# ---------------------------------------------------------------------------

get_var() {
  local key="$1"
  grep -E "^\s*${key}\s*=" "${TFVARS}" \
    | head -1 \
    | sed 's/.*=\s*//' \
    | tr -d '"' \
    | tr -d "'" \
    | sed 's/\s*#.*//' \
    | tr -d ' '
}

SG_NAME=$(get_var security_group_name)
CREATE_SG=$(get_var create_security_group)
NETWORK_NAME=$(get_var network_name)
CREATE_NETWORK=$(get_var create_network)
ROUTER_NAME=$(get_var router_name)
CREATE_ROUTER=$(get_var create_router)
VM_NAME=$(get_var vm_name)

echo "=== Pre-flight idempotency check ==="
echo ""

# ---------------------------------------------------------------------------
# Helper: check if resource already in Terraform state
# ---------------------------------------------------------------------------

in_state() {
  terraform state list 2>/dev/null | grep -qF "${1}"
}

# ---------------------------------------------------------------------------
# Import existing security group if needed
# ---------------------------------------------------------------------------

if [[ "${CREATE_SG}" == "true" && -n "${SG_NAME}" ]]; then
  if in_state "openstack_networking_secgroup_v2.jumpbox[0]"; then
    echo "[SG] Already in state — skipping import."
  else
    echo "[SG] Checking if '${SG_NAME}' exists in OpenStack ..."
    SG_ID=$(python3 - <<PYEOF
import openstack, os, sys
conn = openstack.connect(auth_url=os.environ['OS_AUTH_URL'], insecure=True)
sg = conn.network.find_security_group("${SG_NAME}", ignore_missing=True)
print(sg.id if sg else "")
PYEOF
    )
    if [[ -n "${SG_ID}" ]]; then
      echo "[SG] '${SG_NAME}' exists (${SG_ID}) — importing into Terraform state ..."
      terraform import "openstack_networking_secgroup_v2.jumpbox[0]" "${SG_ID}"
      echo "[SG] Import complete."
    else
      echo "[SG] '${SG_NAME}' not found — Terraform will create it."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Import existing network if needed
# ---------------------------------------------------------------------------

if [[ "${CREATE_NETWORK}" == "true" && -n "${NETWORK_NAME}" ]]; then
  if in_state "openstack_networking_network_v2.jumpbox[0]"; then
    echo "[Network] Already in state — skipping import."
  else
    echo "[Network] Checking if '${NETWORK_NAME}' exists in OpenStack ..."
    NETWORK_ID=$(python3 - <<PYEOF
import openstack, os, sys
conn = openstack.connect(auth_url=os.environ['OS_AUTH_URL'], insecure=True)
net = conn.network.find_network("${NETWORK_NAME}", ignore_missing=True)
print(net.id if net else "")
PYEOF
    )
    if [[ -n "${NETWORK_ID}" ]]; then
      echo "[Network] '${NETWORK_NAME}' exists (${NETWORK_ID}) — importing into Terraform state ..."
      terraform import "openstack_networking_network_v2.jumpbox[0]" "${NETWORK_ID}"
      echo "[Network] Import complete."
    else
      echo "[Network] '${NETWORK_NAME}' not found — Terraform will create it."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Import existing router if needed
# ---------------------------------------------------------------------------

if [[ "${CREATE_ROUTER}" == "true" && -n "${ROUTER_NAME}" ]]; then
  if in_state "openstack_networking_router_v2.jumpbox[0]"; then
    echo "[Router] Already in state — skipping import."
  else
    echo "[Router] Checking if '${ROUTER_NAME}' exists in OpenStack ..."
    ROUTER_ID=$(python3 - <<PYEOF
import openstack, os, sys
conn = openstack.connect(auth_url=os.environ['OS_AUTH_URL'], insecure=True)
router = conn.network.find_router("${ROUTER_NAME}", ignore_missing=True)
print(router.id if router else "")
PYEOF
    )
    if [[ -n "${ROUTER_ID}" ]]; then
      echo "[Router] '${ROUTER_NAME}' exists (${ROUTER_ID}) — importing into Terraform state ..."
      terraform import "openstack_networking_router_v2.jumpbox[0]" "${ROUTER_ID}"
      echo "[Router] Import complete."
    else
      echo "[Router] '${ROUTER_NAME}' not found — Terraform will create it."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Import existing VM instance if needed
# ---------------------------------------------------------------------------

if [[ -n "${VM_NAME}" ]]; then
  if in_state "openstack_compute_instance_v2.jumpbox"; then
    echo "[VM] Already in state — skipping import."
  else
    echo "[VM] Checking if '${VM_NAME}' exists in OpenStack ..."
    VM_ID=$(python3 - <<PYEOF
import openstack, os
conn = openstack.connect(auth_url=os.environ['OS_AUTH_URL'], insecure=True)
server = conn.compute.find_server("${VM_NAME}", ignore_missing=True)
print(server.id if server else "")
PYEOF
    )
    if [[ -n "${VM_ID}" ]]; then
      echo "[VM] '${VM_NAME}' exists (${VM_ID}) — importing into Terraform state ..."
      terraform import "openstack_compute_instance_v2.jumpbox" "${VM_ID}"
      echo "[VM] Import complete — Terraform will manage existing VM, not create a new one."
    else
      echo "[VM] '${VM_NAME}' not found — Terraform will create it."
    fi
  fi
fi

echo ""
echo "=== Running terraform apply ==="
echo ""
terraform apply -var-file="${TFVARS}"
