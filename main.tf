terraform {
  required_version = ">= 1.3"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
  }
}

provider "openstack" {
}

# ---------------------------------------------------------------------------
# Variables — Provider
# ---------------------------------------------------------------------------

variable "cloud_name" {
  description = "Cloud name as defined in clouds.yaml"
  type        = string
  default     = "openstack"
}

# ---------------------------------------------------------------------------
# Variables — Network
# ---------------------------------------------------------------------------

variable "create_network" {
  description = "Set to true to create the network and subnet. Set to false to use an existing network."
  type        = bool
  default     = true
}

variable "network_name" {
  description = "Name of the network to create or look up"
  type        = string
  default     = "jumpbox-network"
}

variable "subnet_name" {
  description = "Name of the subnet to create (only used when create_network = true)"
  type        = string
  default     = "jumpbox-subnet"
}

variable "network_cidr" {
  description = "CIDR block for the subnet (only used when create_network = true)"
  type        = string
  default     = "10.10.0.0/24"
}

variable "dns_nameservers" {
  description = "DNS nameservers for the subnet"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "external_network_name" {
  description = "Name of the external network used for the router gateway. Required only when create_router = true."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Variables — Router
# ---------------------------------------------------------------------------

variable "create_router" {
  description = "Set to true to create a router. Set to false to skip router management (or set router_name to attach to an existing one)."
  type        = bool
  default     = false
}

variable "router_name" {
  description = "Name of the router to create (when create_router=true) or look up (when create_router=false and non-empty). Leave empty to skip router entirely."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Variables — Firewall
# ---------------------------------------------------------------------------

variable "create_security_group" {
  description = "Set to true to create the security group. Set to false to use an existing one."
  type        = bool
  default     = true
}

variable "security_group_name" {
  description = "Name of the security group to create or look up"
  type        = string
  default     = "jumpbox-sg"
}

# SECURITY WARNING: Default CIDRs are broad RFC1918 ranges for initial testing only.
# Restrict these to the smallest possible ranges before deploying to production.
variable "ingress_cidrs" {
  description = "List of CIDRs allowed to connect to the jumpbox"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "egress_cidrs" {
  description = "List of CIDRs the jumpbox is allowed to connect to"
  type        = list(string)
  default     = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
  ]
}

# ---------------------------------------------------------------------------
# Variables — VM
# ---------------------------------------------------------------------------

variable "sectag" {
  description = "Security tag applied to the VM instance metadata"
  type        = string
  default     = "rsz"
}

variable "vm_name" {
  description = "Name of the VM to provision"
  type        = string
  default     = "jumpbox"
}

variable "image_name" {
  description = "Name of the RHEL9 image in OpenStack"
  type        = string
  default     = "rhel9"
}

variable "flavor_name" {
  description = "Flavor name for the VM"
  type        = string
  default     = "m1.medium"
}

variable "availability_zone" {
  description = "Availability zone for the VM"
  type        = string
  default     = "nova"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 50
}

variable "floating_ip_pool" {
  description = "External network name for floating IP allocation. Leave empty to skip."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Variables — cloud-init
# ---------------------------------------------------------------------------

variable "baremetal_user" {
  description = "Username to create via cloud-init"
  type        = string
  default     = "baremetal"
}

# SECURITY WARNING: This default password is a placeholder — override in terraform.tfvars.
# Never commit a real password to version control.
variable "baremetal_password" {
  description = "Default console password for the baremetal user — must be changed on first login"
  type        = string
  default     = "1q2w3e4r"
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key to inject into the baremetal user"
  type        = string
  sensitive   = true
}

variable "packages" {
  description = "Packages to install via cloud-init"
  type        = list(string)
  default     = ["mtr"]
}

variable "syslog_host" {
  description = "Remote syslog host to forward logs to"
  type        = string
  default     = ""
}

variable "syslog_port" {
  description = "Remote syslog port"
  type        = number
  default     = 514
}

# ---------------------------------------------------------------------------
# Image / Flavor
# ---------------------------------------------------------------------------

data "openstack_images_image_v2" "rhel9" {
  name        = var.image_name
  most_recent = true
}

data "openstack_compute_flavor_v2" "jumpbox" {
  name = var.flavor_name
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

data "openstack_networking_network_v2" "external" {
  count = (var.create_router && var.external_network_name != "") ? 1 : 0
  name  = var.external_network_name
}

data "openstack_networking_network_v2" "existing" {
  count = var.create_network ? 0 : 1
  name  = var.network_name
}

resource "openstack_networking_network_v2" "jumpbox" {
  count = var.create_network ? 1 : 0
  name  = var.network_name
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
# Router
# ---------------------------------------------------------------------------

data "openstack_networking_router_v2" "existing" {
  count = (!var.create_router && var.router_name != "") ? 1 : 0
  name  = var.router_name
}

resource "openstack_networking_router_v2" "jumpbox" {
  count               = var.create_router ? 1 : 0
  name                = var.router_name
  external_network_id = var.external_network_name != "" ? data.openstack_networking_network_v2.external[0].id : null
}

locals {
  has_router = var.create_router || (!var.create_router && var.router_name != "")
  router_id  = var.create_router ? openstack_networking_router_v2.jumpbox[0].id : (var.router_name != "" ? data.openstack_networking_router_v2.existing[0].id : null)
}

resource "openstack_networking_router_interface_v2" "jumpbox" {
  count     = (var.create_network && local.has_router) ? 1 : 0
  router_id = local.router_id
  subnet_id = openstack_networking_subnet_v2.jumpbox[0].id
}

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

locals {
  ingress_cidrs       = var.create_security_group ? toset(var.ingress_cidrs) : toset([])
  egress_cidrs        = var.create_security_group ? toset(var.egress_cidrs) : toset([])
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

# ---------------------------------------------------------------------------
# VM Instance
# ---------------------------------------------------------------------------

resource "openstack_compute_instance_v2" "jumpbox" {
  name              = var.vm_name
  flavor_id         = data.openstack_compute_flavor_v2.jumpbox.id
  availability_zone = var.availability_zone
  user_data         = local.cloud_init

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
    sectag         = var.sectag
  }

  lifecycle {
    ignore_changes = [block_device]
  }

  depends_on = [
    openstack_networking_router_interface_v2.jumpbox,
  ]
}

# ---------------------------------------------------------------------------
# Floating IP
# ---------------------------------------------------------------------------

resource "openstack_networking_floatingip_v2" "jumpbox" {
  count = var.floating_ip_pool != "" ? 1 : 0
  pool  = var.floating_ip_pool
}

resource "openstack_networking_floatingip_associate_v2" "jumpbox" {
  count       = var.floating_ip_pool != "" ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.jumpbox[0].address
  port_id     = openstack_compute_instance_v2.jumpbox.network[0].port
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "instance_id" {
  description = "OpenStack instance UUID"
  value       = openstack_compute_instance_v2.jumpbox.id
}

output "instance_ip" {
  description = "Internal IP address of the VM"
  value       = openstack_compute_instance_v2.jumpbox.access_ip_v4
}

output "floating_ip" {
  description = "Floating IP address (if assigned)"
  value       = var.floating_ip_pool != "" ? openstack_networking_floatingip_v2.jumpbox[0].address : null
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value = format(
    "ssh %s@%s",
    var.baremetal_user,
    var.floating_ip_pool != "" ? openstack_networking_floatingip_v2.jumpbox[0].address : openstack_compute_instance_v2.jumpbox.access_ip_v4
  )
}

output "network_id" {
  description = "ID of the network (created or existing)"
  value       = local.network_id
}

output "security_group_name" {
  description = "Name of the security group"
  value       = local.security_group_name
}

output "router_id" {
  description = "ID of the router (created or existing), null if no router"
  value       = local.router_id
}
