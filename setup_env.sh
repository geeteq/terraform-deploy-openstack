#!/usr/bin/env bash
# Source this script before running terraform:
#   source setup_env.sh [clouds.yaml] [cloud-name]

CLOUDS_FILE="${1:-$HOME/.config/openstack/clouds.yaml}"
CLOUD_NAME="${2:-openstack}"

if [[ ! -f "${CLOUDS_FILE}" ]]; then
  echo "ERROR: clouds.yaml not found at ${CLOUDS_FILE}"
  return 1
fi

echo "Loading cloud '${CLOUD_NAME}' from ${CLOUDS_FILE} ..."

eval "$(python3 - "${CLOUDS_FILE}" "${CLOUD_NAME}" <<'PYEOF'
import sys
import yaml

clouds_file = sys.argv[1]
cloud_name  = sys.argv[2]

with open(clouds_file) as f:
    data = yaml.safe_load(f)

cloud = data["clouds"][cloud_name]
auth  = cloud.get("auth", {})

exports = {}

auth_type = cloud.get("auth_type", "password")
exports["OS_AUTH_TYPE"]           = auth_type
exports["OS_AUTH_URL"]            = auth.get("auth_url", "")
exports["OS_INSECURE"]            = "true"
exports["OS_IDENTITY_API_VERSION"] = str(cloud.get("identity_api_version", 3))

if cloud.get("interface"):
    exports["OS_INTERFACE"] = cloud["interface"]
if cloud.get("region_name"):
    exports["OS_REGION_NAME"] = cloud["region_name"]

if auth_type == "v3applicationcredential":
    exports["OS_APPLICATION_CREDENTIAL_ID"]     = auth.get("application_credential_id", "")
    exports["OS_APPLICATION_CREDENTIAL_SECRET"] = auth.get("application_credential_secret", "")
else:
    exports["OS_USERNAME"]            = auth.get("username", "")
    exports["OS_PASSWORD"]            = auth.get("password", "")
    exports["OS_PROJECT_NAME"]        = auth.get("project_name", "")
    exports["OS_PROJECT_DOMAIN_NAME"] = auth.get("project_domain_name", "Default")
    exports["OS_USER_DOMAIN_NAME"]    = auth.get("user_domain_name", "Default")

for k, v in exports.items():
    print(f'export {k}="{v}"')
PYEOF
)"

echo "Auth type: ${OS_AUTH_TYPE}"
echo "Auth URL:  ${OS_AUTH_URL}"
echo "Environment ready — run: terraform plan"
