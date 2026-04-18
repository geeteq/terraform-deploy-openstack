# ---------------------------------------------------------------------------
# Provider
# ---------------------------------------------------------------------------

variable "cloud_name" {
  description = "Cloud name as defined in clouds.yaml"
  type        = string
  default     = "openstack"
}

# ---------------------------------------------------------------------------
# Network
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
# Router
# ---------------------------------------------------------------------------

variable "create_router" {
  description = "Set to true to create a router. Set to false to use an existing router."
  type        = bool
  default     = true
}

variable "router_name" {
  description = "Name of the router to create or look up"
  type        = string
  default     = "jumpbox-router"
}

# ---------------------------------------------------------------------------
# Security group
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

# ---------------------------------------------------------------------------
# VM
# ---------------------------------------------------------------------------

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
  description = "Root volume size in GB — required for zero-disk flavors (e.g. 8cpu-16G-0G)"
  type        = number
  default     = 50
}

variable "floating_ip_pool" {
  description = "External network name for floating IP allocation. Leave empty to skip."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# cloud-init
# ---------------------------------------------------------------------------

variable "baremetal_user" {
  description = "Username to create via cloud-init"
  type        = string
  default     = "baremetal"
}

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
