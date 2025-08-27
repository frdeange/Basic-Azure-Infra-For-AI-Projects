# 07-private-endpoints.tf – Private Connectivity

# Private Endpoints (+ Private DNS Zone Groups)

# Redis Cache
#############################################

# Storage: Blob
resource "azurerm_private_endpoint" "pe_storage_blob" {
  name                = "${var.ai_prefix}-pe-blob"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.privatelink.id

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dg-blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["privatelink.blob.core.windows.net"].id]
  }
}

# Storage: File
resource "azurerm_private_endpoint" "pe_storage_file" {
  name                = "${var.ai_prefix}-pe-file"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.privatelink.id

  private_service_connection {
    name                           = "file"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dg-file"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["privatelink.file.core.windows.net"].id]
  }
}

# Key Vault
resource "azurerm_private_endpoint" "pe_kv" {
  name                = "${var.ai_prefix}-pe-kv"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.privatelink.id

  private_service_connection {
    name                           = "kv"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dg-kv"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["privatelink.vaultcore.azure.net"].id]
  }
}

# Cosmos DB (SQL)
resource "azurerm_private_endpoint" "pe_cosmos" {
  name                = "${var.ai_prefix}-pe-cosmos"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.privatelink.id

  private_service_connection {
    name                           = "cosmos"
    private_connection_resource_id = azurerm_cosmosdb_account.main.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dg-cosmos"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["privatelink.documents.azure.com"].id]
  }
}

# Azure AI Search
resource "azurerm_private_endpoint" "pe_search" {
  name                = "${var.ai_prefix}-pe-search"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.privatelink.id

  private_service_connection {
    name                           = "search"
    private_connection_resource_id = azurerm_search_service.main.id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dg-search"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["privatelink.search.windows.net"].id]
  }
}

# Azure AI Services (Cognitive/Hub)
resource "azurerm_private_endpoint" "pe_cognitive" {
  name                = "${var.ai_prefix}-pe-cognitive"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.privatelink.id

  private_service_connection {
    name                           = "cognitive"
    private_connection_resource_id = azurerm_ai_services.main.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dg-cognitive"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["privatelink.cognitiveservices.azure.com"].id]
  }
}

# Azure AI Foundry (AML workspace subresource)
resource "azurerm_private_endpoint" "pe_foundry" {
  name                = "${var.ai_prefix}-pe-foundry"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.privatelink.id

  private_service_connection {
    name                           = "foundry"
    private_connection_resource_id = azurerm_ai_foundry.main.id
    subresource_names              = ["amlworkspace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dg-foundry"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["privatelink.api.azureml.ms"].id]
  }
}

# Private Endpoint for inbound to Web App
resource "azurerm_private_endpoint" "pe_web" {
  name                = "${var.ai_prefix}-pe-web"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.privatelink.id

  private_service_connection {
    name                           = "web"
    private_connection_resource_id = azurerm_linux_web_app.web.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dg-web"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["privatelink.azurewebsites.net"].id]
  }
}
