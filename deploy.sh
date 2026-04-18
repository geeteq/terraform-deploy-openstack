#!/usr/bin/env bash
# Idempotent Terraform deploy for OpenStack.
# - Imports existing resources into state before applying
# - Removes stale state entries for resources deleted outside Terraform
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
# Parse tfvars
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
# Helpers
# ---------------------------------------------------------------------------

in_state() {
  terraform state list 2>/dev/null | grep -qF "${1}"
}

remove_from_state() {
  echo "  Removing stale state entry: ${1}"
  terraform state rm "${1}" 2>/dev/null || true
}

exists_in_openstack() {
  # $1 = resource type: sg | network | router | vm
  # $2 = name
  python3 - "${1}" "${2}" <<'PYEOF'
import openstack, os, sys

kind = sys.argv[1]
name = sys.argv[2]

conn = openstack.connect(auth_url=os.environ["OS_AUTH_URL"], insecure=True)

if kind == "sg":
    obj = conn.network.find_security_group(name, ignore_missing=True)
elif kind == "network":
    obj = conn.network.find_network(name, ignore_missing=True)
elif kind == "router":
    obj = conn.network.find_router(name, ignore_missing=True)
elif kind == "vm":
    obj = conn.compute.find_server(name, ignore_missing=True)
else:
    obj = None

if obj:
    print(obj.id)
else:
    print("")
PYEOF
}

sync_resource() {
  local label="$1"
  local state_addr="$2"
  local kind="$3"
  local name="$4"

  echo "[${label}] Checking '${name}' ..."

  local os_id
  os_id=$(exists_in_openstack "${kind}" "${name}")

  local in_tf
  in_tf=false
  in_state "${state_addr}" && in_tf=true

  if [[ "${in_tf}" == "true" && -z "${os_id}" ]]; then
    echo "[${label}] Deleted outside Terraform — removing stale state so it can be recreated."
    remove_from_state "${state_addr}"

  elif [[ "${in_tf}" == "false" && -n "${os_id}" ]]; then
    echo "[${label}] Exists in OpenStack (${os_id}) but not in state — importing."
    terraform import "${state_addr}" "${os_id}"
    echo "[${label}] Import complete."

  elif [[ "${in_tf}" == "true" && -n "${os_id}" ]]; then
    echo "[${label}] In sync."

  else
    echo "[${label}] Not found — Terraform will create it."
  fi
}

# ---------------------------------------------------------------------------
# Sync each managed resource
# ---------------------------------------------------------------------------

if [[ "${CREATE_SG}" == "true" && -n "${SG_NAME}" ]]; then
  sync_resource "Security Group" "openstack_networking_secgroup_v2.jumpbox[0]" "sg" "${SG_NAME}"
fi

if [[ "${CREATE_NETWORK}" == "true" && -n "${NETWORK_NAME}" ]]; then
  sync_resource "Network" "openstack_networking_network_v2.jumpbox[0]" "network" "${NETWORK_NAME}"
fi

if [[ "${CREATE_ROUTER}" == "true" && -n "${ROUTER_NAME}" ]]; then
  sync_resource "Router" "openstack_networking_router_v2.jumpbox[0]" "router" "${ROUTER_NAME}"
  # Also clear the router interface from state if router was removed
  if ! in_state "openstack_networking_router_v2.jumpbox[0]"; then
    remove_from_state "openstack_networking_router_interface_v2.jumpbox[0]"
  fi
fi

if [[ -n "${VM_NAME}" ]]; then
  sync_resource "VM" "openstack_compute_instance_v2.jumpbox" "vm" "${VM_NAME}"
fi

echo ""
echo "=== Running terraform apply ==="
echo ""
terraform apply -var-file="${TFVARS}"
