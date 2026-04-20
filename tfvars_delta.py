#!/usr/bin/env python3
"""
Shows the delta between variables declared in main.tf and values set in terraform.tfvars.

Usage:
    python3 tfvars_delta.py
    python3 tfvars_delta.py --main main.tf --tfvars terraform.tfvars
"""

import argparse
import os
import re
import sys

RESET  = "\033[0m"
GREEN  = "\033[32m"
YELLOW = "\033[33m"
RED    = "\033[31m"
BOLD   = "\033[1m"
DIM    = "\033[2m"


def parse_variables(tf_file):
    """Extract variable names and default values from a .tf file."""
    with open(tf_file) as f:
        content = f.read()

    variables = {}
    # Match each variable block
    for match in re.finditer(r'variable\s+"(\w+)"\s*\{([^}]*(?:\{[^}]*\}[^}]*)*)\}', content, re.DOTALL):
        name = match.group(1)
        body = match.group(2)

        default_match = re.search(r'default\s*=\s*(.+?)(?=\n\s*(?:description|type|sensitive|validation|\})|$)', body, re.DOTALL)
        if default_match:
            default = default_match.group(1).strip().rstrip(',')
            variables[name] = default
        else:
            variables[name] = None  # required — no default

    return variables


def parse_tfvars(tfvars_file):
    """Extract key=value pairs from a .tfvars file."""
    values = {}
    if not os.path.exists(tfvars_file):
        return values

    with open(tfvars_file) as f:
        content = f.read()

    # Strip comments
    content = re.sub(r'#.*', '', content)

    # Match assignments (handles strings, numbers, lists, maps)
    for match in re.finditer(r'(\w+)\s*=\s*(.+?)(?=\n\s*\w+\s*=|\Z)', content, re.DOTALL):
        key = match.group(1).strip()
        val = match.group(2).strip().rstrip(',')
        values[key] = val

    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--main",    default="main.tf",           help="Path to main.tf (default: main.tf)")
    parser.add_argument("--tfvars",  default="terraform.tfvars",  help="Path to terraform.tfvars (default: terraform.tfvars)")
    parser.add_argument("--no-color", action="store_true",        help="Disable colour output")
    args = parser.parse_args()

    if args.no_color:
        global RESET, GREEN, YELLOW, RED, BOLD, DIM
        RESET = GREEN = YELLOW = RED = BOLD = DIM = ""

    if not os.path.exists(args.main):
        sys.exit(f"Error: {args.main} not found")

    declared  = parse_variables(args.main)
    overrides = parse_tfvars(args.tfvars)

    tfvars_exists = os.path.exists(args.tfvars)

    overridden  = {k: v for k, v in declared.items() if k in overrides}
    using_default = {k: v for k, v in declared.items() if k not in overrides and v is not None}
    required_missing = {k for k, v in declared.items() if k not in overrides and v is None}
    unknown = {k: v for k, v in overrides.items() if k not in declared}

    print(f"\n{BOLD}Delta: {args.main}  vs  {args.tfvars}{RESET}")
    if not tfvars_exists:
        print(f"{YELLOW}  (terraform.tfvars not found — showing defaults only){RESET}")
    print()

    if overridden:
        print(f"{BOLD}{GREEN}Overridden in tfvars:{RESET}")
        for k in sorted(overridden):
            print(f"  {GREEN}✔ {k}{RESET}")
            print(f"      default : {DIM}{declared[k]}{RESET}")
            print(f"      tfvars  : {GREEN}{overrides[k]}{RESET}")
        print()

    if using_default:
        print(f"{BOLD}{YELLOW}Using default value:{RESET}")
        for k in sorted(using_default):
            print(f"  {YELLOW}~ {k}{RESET} = {DIM}{using_default[k]}{RESET}")
        print()

    if required_missing:
        print(f"{BOLD}{RED}Required — no default, not set in tfvars:{RESET}")
        for k in sorted(required_missing):
            print(f"  {RED}✘ {k}{RESET}")
        print()

    if unknown:
        print(f"{BOLD}{RED}In tfvars but not declared in main.tf:{RESET}")
        for k in sorted(unknown):
            print(f"  {RED}? {k}{RESET} = {overrides[k]}")
        print()

    print(f"{DIM}Summary: {len(overridden)} overridden, {len(using_default)} using defaults, "
          f"{len(required_missing)} required missing, {len(unknown)} unknown{RESET}\n")


if __name__ == "__main__":
    main()
