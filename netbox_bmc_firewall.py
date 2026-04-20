#!/usr/bin/env python3
"""
Queries NetBox for prefixes tagged 'bmc-management-prod' and generates a
Terraform firewall file (firewall_bmc.tf) with ingress rules for ports
22 (SSH/TCP), 443 (HTTPS/TCP), and 161 (SNMP/UDP).

Usage:
    export NETBOX_URL=https://netbox.example.com
    export NETBOX_TOKEN=your-token-here
    python3 netbox_bmc_firewall.py

    # or pass args directly:
    python3 netbox_bmc_firewall.py --url https://netbox.example.com --token abc123

    # write to a custom output file:
    python3 netbox_bmc_firewall.py --output custom.tf
"""

import argparse
import logging
import os
import re
import sys
import warnings

try:
    import requests
    from requests.packages.urllib3.exceptions import InsecureRequestWarning
except ImportError:
    sys.exit("Missing dependency: pip install requests")

TAG = "bmc-management-prod"
OUTPUT_FILE = "firewall_bmc.tf"
RULES = [
    {"port": 22,  "protocol": "tcp", "label": "ssh"},
    {"port": 443, "protocol": "tcp", "label": "https"},
    {"port": 161, "protocol": "udp", "label": "snmp"},
]

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url",      default=os.getenv("NETBOX_URL"),   help="NetBox base URL (env: NETBOX_URL)")
    parser.add_argument("--token",    default=os.getenv("NETBOX_TOKEN"), help="NetBox API token (env: NETBOX_TOKEN)")
    parser.add_argument("--tag",      default=TAG,                        help=f"NetBox tag to filter (default: {TAG})")
    parser.add_argument("--output",   default=OUTPUT_FILE,                help=f"Output .tf file (default: {OUTPUT_FILE})")
    parser.add_argument("--insecure", action="store_true",                help="Disable SSL certificate verification (self-signed certs)")
    parser.add_argument("--ca-cert",  default=os.getenv("NETBOX_CA_CERT"), help="Path to CA bundle for SSL verification (env: NETBOX_CA_CERT)")
    parser.add_argument("--secgroup-id", default=None,
                        help="Security group ID or resource ref. Defaults to openstack_networking_secgroup_v2.jumpbox[0].id")
    return parser.parse_args()


def test_token(base_url, token, verify):
    """Validate the token against /api/users/tokens/ and report permissions."""
    url = f"{base_url.rstrip('/')}/api/users/tokens/"
    headers = {"Authorization": f"Token {token}", "Accept": "application/json"}
    log.info("Testing token against %s", url)
    try:
        resp = requests.get(url, headers=headers, timeout=15, verify=verify)
    except requests.exceptions.ConnectionError as e:
        sys.exit(f"Connection error: {e}")
    except requests.exceptions.SSLError as e:
        sys.exit(f"SSL error: {e}\n  Try --insecure or --ca-cert to handle certificate issues.")

    if resp.status_code == 200:
        data = resp.json()
        count = data.get("count", "?")
        log.info("Token OK — %s token(s) visible to this user", count)
        return
    if resp.status_code == 403:
        sys.exit(
            "Token test failed: 403 Forbidden.\n"
            "  Possible causes:\n"
            "    - Token is invalid or expired\n"
            "    - Token lacks read permission on IPAM prefixes\n"
            "    - NetBox API access is restricted by allowed IPs\n"
            "  Check: NetBox → Admin → API Tokens and verify the token is active."
        )
    if resp.status_code == 401:
        sys.exit("Token test failed: 401 Unauthorized — token is missing or malformed.")

    resp.raise_for_status()


def fetch_prefixes(base_url, token, tag, verify):
    url = f"{base_url.rstrip('/')}/api/ipam/prefixes/"
    headers = {"Authorization": f"Token {token}", "Accept": "application/json"}
    prefixes = []
    params = {"tag": tag, "limit": 100, "offset": 0}

    while True:
        log.info("GET %s  (offset=%d)", url, params["offset"])
        resp = requests.get(url, headers=headers, params=params, timeout=15, verify=verify)
        if resp.status_code == 403:
            sys.exit("403 Forbidden fetching prefixes — token may lack IPAM read permissions.")
        resp.raise_for_status()
        data = resp.json()
        results = data.get("results", [])
        prefixes.extend(r["prefix"] for r in results)
        log.info("  fetched %d prefix(es), total so far: %d", len(results), len(prefixes))
        if not data.get("next"):
            break
        params["offset"] += params["limit"]

    return prefixes


def cidr_to_id(cidr):
    """Turn '10.0.1.0/24' into 'bmc_10_0_1_0_24' for use as a TF resource name."""
    return "bmc_" + re.sub(r"[./]", "_", cidr)


def render_tf(prefixes, secgroup_ref, tag):
    lines = [
        "# ---------------------------------------------------------------------------",
        f"# BMC Management firewall rules — generated from NetBox tag: {tag}",
        f"# Prefixes: {len(prefixes)}",
        "# DO NOT EDIT — re-run netbox_bmc_firewall.py to regenerate",
        "# ---------------------------------------------------------------------------",
        "",
    ]

    if not prefixes:
        lines.append("# No prefixes found for the given tag.")
        return "\n".join(lines)

    for cidr in sorted(prefixes):
        id_base = cidr_to_id(cidr)
        lines.append(f"# {cidr}")
        for rule in RULES:
            resource_name = f"{id_base}_{rule['label']}_ingress"
            lines += [
                f'resource "openstack_networking_secgroup_rule_v2" "{resource_name}" {{',
                f'  direction         = "ingress"',
                f'  ethertype         = "IPv4"',
                f'  protocol          = "{rule["protocol"]}"',
                f'  port_range_min    = {rule["port"]}',
                f'  port_range_max    = {rule["port"]}',
                f'  remote_ip_prefix  = "{cidr}"',
                f'  security_group_id = {secgroup_ref}',
                f'}}',
                "",
            ]

    return "\n".join(lines)


def main():
    args = parse_args()

    if not args.url:
        sys.exit("Error: NetBox URL required (--url or NETBOX_URL env var)")
    if not args.token:
        sys.exit("Error: NetBox token required (--token or NETBOX_TOKEN env var)")

    secgroup_ref = args.secgroup_id or "openstack_networking_secgroup_v2.egress[0].id"

    if args.insecure:
        warnings.filterwarnings("ignore", category=InsecureRequestWarning)
        log.warning("SSL verification disabled — connection is not fully secure")
        verify = False
    elif args.ca_cert:
        verify = args.ca_cert
    else:
        verify = True

    test_token(args.url, args.token, verify)
    log.info("Fetching prefixes tagged '%s' from %s", args.tag, args.url)
    prefixes = fetch_prefixes(args.url, args.token, args.tag, verify)
    log.info("Found %d prefix(es)", len(prefixes))
    for p in sorted(prefixes):
        log.info("  %s", p)

    tf_content = render_tf(prefixes, secgroup_ref, args.tag)

    with open(args.output, "w") as f:
        f.write(tf_content)

    log.info("Written to %s", args.output)
    log.info("Run 'terraform plan' to review changes before applying.")


if __name__ == "__main__":
    main()
