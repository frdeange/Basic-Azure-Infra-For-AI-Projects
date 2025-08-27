#############################################
# 09-apim.tf – API Management + Backend OpenAI
#############################################

resource "azurerm_api_management" "main" {
  name                 = "${var.ai_prefix}-apim"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  publisher_name       = "AI Team"
  publisher_email      = "ai-team@example.com"
  sku_name             = "Developer_1"
  # Switch to Internal mode: endpoints (gateway/portal/mgmt) only accessible inside VNet
  virtual_network_type = "Internal"

  # VNet integration
  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim.id
  }

  identity {
    type = "SystemAssigned"
  }

  # Extended timeouts for slow APIM deployments (Developer SKU can exceed 45m)
  timeouts {
    create = "2h"
    update = "2h"
    delete = "2h"
  }
  depends_on = [azurerm_subnet_network_security_group_association.apim_nsg_assoc]
}

resource "azurerm_api_management_backend" "openai" {
  name                = "openai-backend"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  protocol            = "http"
  # Use private FQDN (cognitiveservices) via Private DNS instead of fixed private endpoint IP for resiliency
  url         = "https://${azurerm_ai_services.main.custom_subdomain_name}.cognitiveservices.azure.com"
  description = "Azure OpenAI (Cognitive Services) backend via Private Endpoint"

  # Authentication: Managed Identity (no API key required)
}

# Note: For production adjust SKU and publisher_email accordingly.
