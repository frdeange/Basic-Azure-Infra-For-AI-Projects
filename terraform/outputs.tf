# outputs.tf

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "application_gateway_public_ip" {
  value = azurerm_public_ip.agw.ip_address
}

output "webapp_default_hostname" {
  value = azurerm_linux_web_app.web.default_hostname
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "cosmosdb_account_name" {
  value = azurerm_cosmosdb_account.main.name
}

output "search_service_name" {
  value = azurerm_search_service.main.name
}

output "ai_services_name" {
  value = azurerm_ai_services.main.name
}

output "ai_foundry_name" {
  value = azurerm_ai_foundry.main.name
}

output "ai_foundry_project_name" {
  value = azurerm_ai_foundry_project.main.name
}

output "redis_cache_name" {
  value = module.redis_cache.name
}

output "redis_cache_hostname" {
  value = module.redis_cache.hostname
}

output "redis_cache_port" {
  value = module.redis_cache.port
}

output "redis_cache_primary_connection_string" {
  value     = module.redis_cache.primary_connection_string
  sensitive = true
}

# Remote Access Outputs (conditional)
output "bastion_public_ip" {
  description = "Bastion public IP address (if enabled)"
  value       = try(azurerm_public_ip.bastion[0].ip_address, null)
}

output "bastion_fqdn" {
  description = "Bastion FQDN (if enabled)"
  value       = try(azurerm_public_ip.bastion[0].fqdn, null)
}

output "jumpbox_private_ip" {
  description = "JumpBox private IP (if enabled)"
  value       = try(azurerm_network_interface.jumpbox[0].private_ip_address, null)
}

output "jumpbox_ssh_private_key_pem" {
  description = "Auto-generated SSH private key for the JumpBox (if no key was provided). Keep it secure."
  value       = try(tls_private_key.jumpbox[0].private_key_pem, null)
  sensitive   = true
}

output "vpn_gateway_public_ip" {
  description = "VPN Gateway public IP (if enabled)"
  value       = try(azurerm_public_ip.vpngw[0].ip_address, null)
}

# APIM Internal endpoints: In Internal mode there is no public IP; expose the name and internal gateway URL.
output "apim_name" {
  description = "APIM service name"
  value       = azurerm_api_management.main.name
}

output "apim_internal_gateway_url" {
  description = "Internal APIM gateway URL (requires internal DNS resolution)"
  value       = azurerm_api_management.main.gateway_url
}

