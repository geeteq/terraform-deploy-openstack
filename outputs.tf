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
  description = "Name of the security group (created or existing)"
  value       = local.security_group_name
}

output "router_id" {
  description = "ID of the router (created or existing)"
  value       = var.create_router ? openstack_networking_router_v2.jumpbox[0].id : data.openstack_networking_router_v2.existing[0].id
}
