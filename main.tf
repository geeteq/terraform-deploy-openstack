terraform {
  required_version = ">= 1.3"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
  }

  backend "http" {}
}

provider "openstack" {
  insecure = true
}

# ---------------------------------------------------------------------------
# Image / Flavor (always looked up, never created)
# ---------------------------------------------------------------------------

data "openstack_images_image_v2" "rhel9" {
  name        = var.image_name
  most_recent = true
}

data "openstack_compute_flavor_v2" "jumpbox" {
  name = var.flavor_name
}

# ---------------------------------------------------------------------------
# External network — only looked up when creating a router or floating IP
# ---------------------------------------------------------------------------

data "openstack_networking_network_v2" "external" {
  count = (var.create_router && var.external_network_name != "") ? 1 : 0
  name  = var.external_network_name
}

# ---------------------------------------------------------------------------
# Network — create or look up existing
# ---------------------------------------------------------------------------

data "openstack_networking_network_v2" "existing" {
  count = var.create_network ? 0 : 1
  name  = var.network_name
}

resource "openstack_networking_network_v2" "jumpbox" {
  count          = var.create_network ? 1 : 0
  name           = var.network_name
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "jumpbox" {
  count           = var.create_network ? 1 : 0
  name            = var.subnet_name
  network_id      = openstack_networking_network_v2.jumpbox[0].id
  cidr            = var.network_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers
}

# ---------------------------------------------------------------------------
# Router — create or look up existing
# ---------------------------------------------------------------------------

data "openstack_networking_router_v2" "existing" {
  count = var.create_router ? 0 : 1
  name  = var.router_name
}

resource "openstack_networking_router_v2" "jumpbox" {
  count               = var.create_router ? 1 : 0
  name                = var.router_name
  admin_state_up      = true
  external_network_id = var.external_network_name != "" ? data.openstack_networking_network_v2.external[0].id : null
}

# Attach new subnet to router (works whether router is new or existing)
resource "openstack_networking_router_interface_v2" "jumpbox" {
  count     = var.create_network ? 1 : 0
  router_id = var.create_router ? openstack_networking_router_v2.jumpbox[0].id : data.openstack_networking_router_v2.existing[0].id
  subnet_id = openstack_networking_subnet_v2.jumpbox[0].id
}

# ---------------------------------------------------------------------------
# Security group — create or look up existing
# ---------------------------------------------------------------------------

data "openstack_networking_secgroup_v2" "existing" {
  count = var.create_security_group ? 0 : 1
  name  = var.security_group_name
}

resource "openstack_networking_secgroup_v2" "jumpbox" {
  count       = var.create_security_group ? 1 : 0
  name        = var.security_group_name
  description = "Jumpbox security group — SSH (22) and HTTPS (443)"
}

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

# ---------------------------------------------------------------------------
# Locals — resolve created vs existing resources
# ---------------------------------------------------------------------------

locals {
  network_id          = var.create_network ? openstack_networking_network_v2.jumpbox[0].id : data.openstack_networking_network_v2.existing[0].id
  security_group_name = var.create_security_group ? openstack_networking_secgroup_v2.jumpbox[0].name : data.openstack_networking_secgroup_v2.existing[0].name

  cloud_init = templatefile("${path.module}/cloud_init.tftpl", {
    baremetal_user     = var.baremetal_user
    baremetal_password = var.baremetal_password
    ssh_public_key     = var.ssh_public_key
    packages           = var.packages
    syslog_host        = var.syslog_host
    syslog_port        = var.syslog_port
  })
}

# ---------------------------------------------------------------------------
# VM instance
# ---------------------------------------------------------------------------

resource "openstack_compute_instance_v2" "jumpbox" {
  name              = var.vm_name
  flavor_id         = data.openstack_compute_flavor_v2.jumpbox.id
  availability_zone = var.availability_zone
  user_data         = local.cloud_init

  # Boot from a volume — required for zero-disk flavors
  block_device {
    uuid                  = data.openstack_images_image_v2.rhel9.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = var.root_volume_size
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    uuid = local.network_id
  }

  security_groups = [local.security_group_name]

  metadata = {
    provisioned_by = "terraform-deploy-openstack"
    managed        = "true"
  }

  lifecycle {
    ignore_changes = [block_device]
  }

  depends_on = [
    openstack_networking_router_interface_v2.jumpbox,
  ]
}

# ---------------------------------------------------------------------------
# Floating IP — only when floating_ip_pool is set
# ---------------------------------------------------------------------------

resource "openstack_networking_floatingip_v2" "jumpbox" {
  count = var.floating_ip_pool != "" ? 1 : 0
  pool  = var.floating_ip_pool
}

resource "openstack_compute_floatingip_associate_v2" "jumpbox" {
  count       = var.floating_ip_pool != "" ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.jumpbox[0].address
  instance_id = openstack_compute_instance_v2.jumpbox.id
}
