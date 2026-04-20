# ---------------------------------------------------------------------------
# Firewall — Zone: ingress (who can talk TO the jumpbox)
# ---------------------------------------------------------------------------

data "openstack_networking_secgroup_v2" "ingress_existing" {
  count = var.create_security_groups ? 0 : 1
  name  = var.ingress_security_group_name
}

resource "openstack_networking_secgroup_v2" "ingress" {
  count       = var.create_security_groups ? 1 : 0
  name        = var.ingress_security_group_name
  description = "Ingress zone — who is allowed to connect to the jumpbox"
}

resource "openstack_networking_secgroup_rule_v2" "ssh_ingress" {
  count             = var.create_security_groups ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ingress_cidr
  security_group_id = openstack_networking_secgroup_v2.ingress[0].id
}

resource "openstack_networking_secgroup_rule_v2" "https_ingress" {
  count             = var.create_security_groups ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = var.ingress_cidr
  security_group_id = openstack_networking_secgroup_v2.ingress[0].id
}

# ---------------------------------------------------------------------------
# Firewall — Zone: egress (what the jumpbox is allowed to talk TO)
# ---------------------------------------------------------------------------

data "openstack_networking_secgroup_v2" "egress_existing" {
  count = var.create_security_groups ? 0 : 1
  name  = var.egress_security_group_name
}

resource "openstack_networking_secgroup_v2" "egress" {
  count       = var.create_security_groups ? 1 : 0
  name        = var.egress_security_group_name
  description = "Egress zone — where the jumpbox is allowed to connect to"
}

resource "openstack_networking_secgroup_rule_v2" "ssh_egress" {
  count             = var.create_security_groups ? 1 : 0
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.egress_cidr
  security_group_id = openstack_networking_secgroup_v2.egress[0].id
}

resource "openstack_networking_secgroup_rule_v2" "https_egress" {
  count             = var.create_security_groups ? 1 : 0
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = var.egress_cidr
  security_group_id = openstack_networking_secgroup_v2.egress[0].id
}
