output "fw1_management_public_ip" {
  description = "FW1 management public IP (SSH/HTTPS access)."
  value       = azurerm_public_ip.management[0].ip_address
}

output "fw2_management_public_ip" {
  description = "FW2 management public IP (SSH/HTTPS access)."
  value       = azurerm_public_ip.management[1].ip_address
}

output "fw1_management_private_ip" {
  description = "FW1 management private IP."
  value       = azurerm_network_interface.management[0].private_ip_address
}

output "fw2_management_private_ip" {
  description = "FW2 management private IP."
  value       = azurerm_network_interface.management[1].private_ip_address
}

output "external_lb_public_ip" {
  description = "External (untrust) load balancer public IP — use this as the WAN-side entry point."
  value       = azurerm_public_ip.external_lb.ip_address
}

output "internal_lb_private_ip" {
  description = "Internal (trust) load balancer private IP — use as next-hop in spoke UDRs."
  value       = azurerm_lb.internal.frontend_ip_configuration[0].private_ip_address
}

output "fw1_untrust_private_ip" {
  description = "FW1 untrust NIC private IP."
  value       = azurerm_network_interface.untrust[0].private_ip_address
}

output "fw2_untrust_private_ip" {
  description = "FW2 untrust NIC private IP."
  value       = azurerm_network_interface.untrust[1].private_ip_address
}

output "fw1_trust_private_ip" {
  description = "FW1 trust NIC private IP."
  value       = azurerm_network_interface.trust[0].private_ip_address
}

output "fw2_trust_private_ip" {
  description = "FW2 trust NIC private IP."
  value       = azurerm_network_interface.trust[1].private_ip_address
}

output "fw1_ha2_private_ip" {
  description = "FW1 HA2 NIC private IP."
  value       = azurerm_network_interface.ha2[0].private_ip_address
}

output "fw2_ha2_private_ip" {
  description = "FW2 HA2 NIC private IP."
  value       = azurerm_network_interface.ha2[1].private_ip_address
}
