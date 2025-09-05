#############################################
# 10-private-endpoints.tf – Private Endpoints (was 07-private-endpoints.tf)
#############################################

resource "azurerm_private_endpoint" "pe_storage_blob" {
  name                = "${local.base_prefix}-pe-blob"
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

resource "azurerm_private_endpoint" "pe_storage_file" {
  name                = "${local.base_prefix}-pe-file"
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

resource "azurerm_private_endpoint" "pe_kv" {
  name                = "${local.base_prefix}-pe-kv"
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

resource "azurerm_private_endpoint" "pe_cosmos" {
  name                = "${local.base_prefix}-pe-cosmos"
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

resource "azurerm_private_endpoint" "pe_search" {
  name                = "${local.base_prefix}-pe-search"
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

resource "azurerm_private_endpoint" "pe_cognitive" {
  depends_on = [azurerm_ai_services.main]
  name                = "${local.base_prefix}-pe-cognitive"
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

resource "azurerm_private_endpoint" "pe_foundry" {
  name                = "${local.base_prefix}-pe-foundry"
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

resource "azurerm_private_endpoint" "pe_web" {
  name                = "${local.base_prefix}-pe-web"
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

# Managed Redis Private Endpoint (preview) – may require feature registration.
resource "azurerm_private_endpoint" "pe_managed_redis" {
  count               = var.enable_managed_redis && var.enable_managed_redis_private_endpoint ? 1 : 0
  name                = "${local.base_prefix}-pe-redis"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = try(azurerm_subnet.redis[0].id, azurerm_subnet.privatelink.id)

  private_service_connection {
    name                           = "redis"
    private_connection_resource_id = azapi_resource.managed_redis[0].id
    subresource_names              = ["redisEnterprise"]
    is_manual_connection           = false
  }

  # DNS zone currently reused (if available). Managed Redis may need dedicated zone when GA.
  # Skipping DNS zone group until official privatelink zone is published.
}
