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

try:
    import requests
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
    parser.add_argument("--url",    default=os.getenv("NETBOX_URL"),   help="NetBox base URL (env: NETBOX_URL)")
    parser.add_argument("--token",  default=os.getenv("NETBOX_TOKEN"), help="NetBox API token (env: NETBOX_TOKEN)")
    parser.add_argument("--tag",    default=TAG,                        help=f"NetBox tag to filter (default: {TAG})")
    parser.add_argument("--output", default=OUTPUT_FILE,                help=f"Output .tf file (default: {OUTPUT_FILE})")
    parser.add_argument("--secgroup-id", default=None,
                        help="Security group ID or resource ref. Defaults to openstack_networking_secgroup_v2.jumpbox[0].id")
    return parser.parse_args()


def fetch_prefixes(base_url, token, tag):
    url = f"{base_url.rstrip('/')}/api/ipam/prefixes/"
    headers = {"Authorization": f"Token {token}", "Accept": "application/json"}
    prefixes = []
    params = {"tag": tag, "limit": 100, "offset": 0}

    while True:
        log.info("GET %s  (offset=%d)", url, params["offset"])
        resp = requests.get(url, headers=headers, params=params, timeout=15)
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

    secgroup_ref = args.secgroup_id or "openstack_networking_secgroup_v2.jumpbox[0].id"

    log.info("Fetching prefixes tagged '%s' from %s", args.tag, args.url)
    prefixes = fetch_prefixes(args.url, args.token, args.tag)
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
