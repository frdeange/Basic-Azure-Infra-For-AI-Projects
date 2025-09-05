#############################################
# 17-rbac.tf – Role Assignments (was 08-rbac.tf)
#############################################

resource "azurerm_role_assignment" "apim_openai_access" {
  scope                            = azurerm_ai_services.main.id
  role_definition_name             = "Cognitive Services User"
  principal_id                     = azurerm_api_management.main.identity[0].principal_id
  skip_service_principal_aad_check = true
}


## Removed duplicate Storage Blob Data Contributor assignment (already granted manually or previously). Comment retained for reference.
# resource "azurerm_role_assignment" "foundry_storage_contrib" {
#   scope                            = azurerm_storage_account.main.id
#   role_definition_name             = "Storage Blob Data Contributor"
#   principal_id                     = azurerm_ai_foundry.main.identity[0].principal_id
#   skip_service_principal_aad_check = true
# }

resource "azurerm_role_assignment" "foundry_kv_secrets_user" {
  scope                            = azurerm_key_vault.main.id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_ai_foundry.main.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Application Gateway needs to read SSL certificate from Key Vault
resource "azurerm_role_assignment" "agw_kv_cert_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = azurerm_user_assigned_identity.agw.principal_id
  skip_service_principal_aad_check = true
}

# Application Gateway also needs secret read access for the certificate's secret material
resource "azurerm_role_assignment" "agw_kv_secret_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.agw.principal_id
  skip_service_principal_aad_check = true
}

# Web App (if it needs to read secrets/certificates)
resource "azurerm_role_assignment" "web_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.web.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# APIM (if it needs to read secrets/certificates)
resource "azurerm_role_assignment" "apim_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_api_management.main.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Terraform deployer (user/service principal) needs to read/write certificates in Key Vault
## Removed deployer_kv_cert_officer assignment; interactive deploy expects existing permissions or can be re-added with explicit object id.
# resource "azurerm_role_assignment" "deployer_kv_cert_officer" {
#   scope                = azurerm_key_vault.main.id
#   role_definition_name = "Key Vault Certificates Officer"
#   principal_id         = coalesce(trimspace(var.terraform_deployer_object_id) != "" ? var.terraform_deployer_object_id : null, data.azurerm_client_config.current.object_id)
#   skip_service_principal_aad_check = true
#   depends_on           = [azurerm_key_vault.main]
# }
