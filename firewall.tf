# ---------------------------------------------------------------------------
# Firewall (Security Group)
# ---------------------------------------------------------------------------

data "openstack_networking_secgroup_v2" "existing" {
  count = var.create_security_group ? 0 : 1
  name  = var.security_group_name
}

resource "openstack_networking_secgroup_v2" "jumpbox" {
  count       = var.create_security_group ? 1 : 0
  name        = var.security_group_name
  description = "Jumpbox firewall — SSH and HTTPS ingress/egress"
}

# Ingress

# Ingress

locals {
  ingress_cidrs = var.create_security_group ? toset(var.ingress_cidrs) : toset([])
  egress_cidrs  = var.create_security_group ? toset(var.egress_cidrs) : toset([])
}

resource "openstack_networking_secgroup_rule_v2" "ssh_ingress" {
  for_each          = local.ingress_cidrs
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.jumpbox[0].id
}

resource "openstack_networking_secgroup_rule_v2" "https_ingress" {
  for_each          = local.ingress_cidrs
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.jumpbox[0].id
}

# Egress

resource "openstack_networking_secgroup_rule_v2" "ssh_egress" {
  for_each          = local.egress_cidrs
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.jumpbox[0].id
}

resource "openstack_networking_secgroup_rule_v2" "https_egress" {
  for_each          = local.egress_cidrs
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.jumpbox[0].id
}
