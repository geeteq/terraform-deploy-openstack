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
  description = "Default firewall — SSH (22) and HTTPS (443) ingress/egress"
}

# Ingress rules

resource "openstack_networking_secgroup_rule_v2" "ssh_ingress" {
  count             = var.create_security_group ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.jumpbox[0].id
}

resource "openstack_networking_secgroup_rule_v2" "https_ingress" {
  count             = var.create_security_group ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.jumpbox[0].id
}

# Egress rules

resource "openstack_networking_secgroup_rule_v2" "ssh_egress" {
  count             = var.create_security_group ? 1 : 0
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.jumpbox[0].id
}

resource "openstack_networking_secgroup_rule_v2" "https_egress" {
  count             = var.create_security_group ? 1 : 0
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.jumpbox[0].id
}
