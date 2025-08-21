#############################################
# outputs.tf
#############################################

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
