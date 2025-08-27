#############################################
# 03-ai-services.tf – Azure AI Platform
#############################################

#############################################
# Azure AI Services Hub + Foundry + Project
#############################################
resource "azurerm_ai_services" "main" {
  name                  = lower(var.ai_services_name)
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  sku_name              = "S0"
  custom_subdomain_name = "${var.ai_prefix}-cognitive"
}

resource "azurerm_ai_foundry" "main" {
  name                = lower(var.ai_foundry_name)
  location            = azurerm_ai_services.main.location
  resource_group_name = azurerm_resource_group.main.name
  storage_account_id  = azurerm_storage_account.main.id
  key_vault_id        = azurerm_key_vault.main.id

  identity { type = "SystemAssigned" }
}

resource "azurerm_ai_foundry_project" "main" {
  name               = lower(var.ai_foundry_project_name)
  location           = azurerm_ai_foundry.main.location
  ai_services_hub_id = azurerm_ai_foundry.main.id

  identity {
    type = "SystemAssigned"
  }

}
