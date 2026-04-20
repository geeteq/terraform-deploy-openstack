#!/usr/bin/env bash
# Idempotent Terraform deploy for OpenStack.
# - Imports existing resources into state before applying
# - Removes stale state entries for resources deleted outside Terraform
# - Skips apply entirely if nothing has changed
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
SUBNET_NAME=$(get_var subnet_name)
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
  # $1 = resource type: sg | network | router | vm | router_iface
  # $2 = name  (for router_iface: "<router_id>/<subnet_name>")
  python3 - "${1}" "${2}" <<'PYEOF'
import openstack, os, sys

kind = sys.argv[1]
name = sys.argv[2]

conn = openstack.connect(auth_url=os.environ["OS_AUTH_URL"], insecure=True)

if kind == "sg":
    obj = conn.network.find_security_group(name, ignore_missing=True)
    print(obj.id if obj else "")

elif kind == "network":
    obj = conn.network.find_network(name, ignore_missing=True)
    print(obj.id if obj else "")

elif kind == "router":
    obj = conn.network.find_router(name, ignore_missing=True)
    print(obj.id if obj else "")

elif kind == "vm":
    obj = conn.compute.find_server(name, ignore_missing=True)
    print(obj.id if obj else "")

elif kind == "subnet":
    obj = conn.network.find_subnet(name, ignore_missing=True)
    print(obj.id if obj else "")

elif kind == "router_iface":
    # name = "<router_id>/<subnet_name>"
    router_id, subnet_name = name.split("/", 1)
    subnet = conn.network.find_subnet(subnet_name, ignore_missing=True)
    if not subnet:
        print("")
        sys.exit(0)
    # Walk all ports on the router and match by subnet_id
    for port in conn.network.ports(device_id=router_id):
        for fixed_ip in port.fixed_ips:
            if fixed_ip.get("subnet_id") == subnet.id:
                # Terraform imports router_iface by subnet_id (when created with subnet_id)
                print(subnet.id)
                sys.exit(0)
    print("")

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

if [[ "${CREATE_NETWORK}" == "true" && -n "${SUBNET_NAME}" ]]; then
  sync_resource "Subnet" "openstack_networking_subnet_v2.jumpbox[0]" "subnet" "${SUBNET_NAME}"
fi

EXTRA_VARS=""

if [[ -n "${ROUTER_NAME}" ]]; then
  echo "[Router] Checking '${ROUTER_NAME}' ..."

  ROUTER_OS_ID=$(exists_in_openstack "router" "${ROUTER_NAME}")

  if [[ "${CREATE_ROUTER}" == "true" ]]; then
    if in_state "openstack_networking_router_v2.jumpbox[0]" && [[ -z "${ROUTER_OS_ID}" ]]; then
      echo "[Router] Deleted outside Terraform — removing stale state so it can be recreated."
      remove_from_state "openstack_networking_router_v2.jumpbox[0]"
      remove_from_state "openstack_networking_router_interface_v2.jumpbox[0]"
    elif ! in_state "openstack_networking_router_v2.jumpbox[0]" && [[ -n "${ROUTER_OS_ID}" ]]; then
      echo "[Router] Exists in OpenStack (${ROUTER_OS_ID}) — importing."
      terraform import "openstack_networking_router_v2.jumpbox[0]" "${ROUTER_OS_ID}"
    elif [[ -n "${ROUTER_OS_ID}" ]]; then
      echo "[Router] In sync."
    else
      echo "[Router] Not found — Terraform will create it."
    fi
  else
    if [[ -z "${ROUTER_OS_ID}" ]]; then
      echo "[Router] '${ROUTER_NAME}' not found in OpenStack but create_router = false."
      echo "[Router] Overriding to create_router = true so Terraform recreates it."
      EXTRA_VARS="-var=create_router=true"
    else
      echo "[Router] Exists (${ROUTER_OS_ID}) — data source will resolve it."
    fi
  fi

  # Sync the router interface — missing from state causes RouterInUse on re-runs
  if [[ "${CREATE_NETWORK}" == "true" && -n "${ROUTER_OS_ID}" && -n "${SUBNET_NAME}" ]]; then
    echo "[Router Interface] Checking subnet port attachment '${SUBNET_NAME}' ..."
    if ! in_state "openstack_networking_router_interface_v2.jumpbox[0]"; then
      IFACE_SUBNET_ID=$(exists_in_openstack "router_iface" "${ROUTER_OS_ID}/${SUBNET_NAME}")
      if [[ -n "${IFACE_SUBNET_ID}" ]]; then
        echo "[Router Interface] Port exists but not in state — importing (subnet ${IFACE_SUBNET_ID})."
        terraform import "openstack_networking_router_interface_v2.jumpbox[0]" "${IFACE_SUBNET_ID}"
        echo "[Router Interface] Import complete."
      else
        echo "[Router Interface] Not found — Terraform will create it."
      fi
    else
      echo "[Router Interface] In sync."
    fi
  fi
fi

if [[ -n "${VM_NAME}" ]]; then
  sync_resource "VM" "openstack_compute_instance_v2.jumpbox" "vm" "${VM_NAME}"
fi

# ---------------------------------------------------------------------------
# Plan — skip apply if nothing has changed
# ---------------------------------------------------------------------------

echo ""
echo "=== Checking for changes ==="
echo ""

set +e
terraform plan -var-file="${TFVARS}" ${EXTRA_VARS} -detailed-exitcode -out=tfplan.out 2>&1
PLAN_EXIT=$?
set -e

# exit code 0 = no changes, 1 = error, 2 = changes pending
if [[ ${PLAN_EXIT} -eq 0 ]]; then
  echo ""
  echo "=== No changes — infrastructure is up to date. Nothing to apply. ==="
  rm -f tfplan.out
  exit 0
elif [[ ${PLAN_EXIT} -eq 1 ]]; then
  echo ""
  echo "ERROR: terraform plan failed."
  rm -f tfplan.out
  exit 1
fi

echo ""
echo "=== Applying changes ==="
echo ""
terraform apply tfplan.out
rm -f tfplan.out
