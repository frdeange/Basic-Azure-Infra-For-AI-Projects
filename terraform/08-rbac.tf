resource "azurerm_role_assignment" "apim_openai_access" {
  scope                            = azurerm_ai_services.main.id
  role_definition_name             = "Cognitive Services User"
  principal_id                     = azurerm_api_management.main.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# RBAC: APIM y OpenAI acceso a Redis Cache
resource "azurerm_role_assignment" "apim_redis_contrib" {
  scope                            = module.redis_cache.id
  role_definition_name             = "Contributor"
  principal_id                     = azurerm_api_management.main.identity[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "openai_redis_contrib" {
  count                            = length(azurerm_ai_services.main.identity)
  scope                            = module.redis_cache.id
  role_definition_name             = "Contributor"
  principal_id                     = azurerm_ai_services.main.identity[count.index].principal_id
  skip_service_principal_aad_check = true
}
# 08-rbac.tf – Role Assignments and Permissions

# RBAC: Foundry to Storage + Key Vault
resource "azurerm_role_assignment" "foundry_storage_contrib" {
  scope                            = azurerm_storage_account.main.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_ai_foundry.main.identity[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "foundry_kv_secrets_user" {
  scope                            = azurerm_key_vault.main.id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_ai_foundry.main.identity[0].principal_id
  skip_service_principal_aad_check = true
}
