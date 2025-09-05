#############################################
# 07-redis-data-platform.tf – Managed Redis (AzAPI), Cosmos DB, Search
#############################################

locals {
  managed_redis_name = lower("${local.base_prefix}-redis")
}

# Azure Managed Redis (preview via AzAPI) – cluster
resource "azapi_resource" "managed_redis" {
  count     = var.enable_managed_redis ? 1 : 0
  type      = "Microsoft.Cache/redisEnterprise@2025-05-01-preview"
  name      = local.managed_redis_name
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id
  # kind not included because AzAPI schema may not accept it explicitly (preview)

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      highAvailability  = var.managed_redis_high_availability ? "Enabled" : "Disabled"
      minimumTlsVersion = "1.2"
    }
    sku = {
      name = var.managed_redis_sku
    }
  }

  schema_validation_enabled = true
}

# Azure Managed Redis database – default
resource "azapi_resource" "managed_redis_database" {
  count     = var.enable_managed_redis ? 1 : 0
  type      = "Microsoft.Cache/redisEnterprise/databases@2025-05-01-preview"
  name      = "default"
  parent_id = azapi_resource.managed_redis[0].id

  body = {
    properties = {
      clientProtocol           = "Encrypted"
      clusteringPolicy         = var.managed_redis_clustering_policy
      evictionPolicy           = var.managed_redis_eviction_policy
      deferUpgrade             = "NotDeferred"
      persistence = {
        aofEnabled = false
        rdbEnabled = false
      }
      accessKeysAuthentication = var.managed_redis_access_keys_auth_enabled ? "Enabled" : "Disabled"
      modules = [for m in var.managed_redis_modules : {
        name = m
      }]
    }
  }

  schema_validation_enabled = true

  depends_on = [azapi_resource.managed_redis]
}

# Data resources to get Redis Enterprise access keys and connection info
data "azapi_resource_action" "redis_access_keys" {
  count       = var.enable_managed_redis ? 1 : 0
  type        = "Microsoft.Cache/redisEnterprise/databases@2025-05-01-preview"
  # Must target the database resource (cluster id would mismatch the type)
  resource_id = azapi_resource.managed_redis_database[0].id
  action      = "listKeys"
  depends_on  = [azapi_resource.managed_redis_database]
}

data "azapi_resource" "redis_primary" {
  count       = var.enable_managed_redis ? 1 : 0
  type        = "Microsoft.Cache/redisEnterprise@2025-05-01-preview"
  resource_id = azapi_resource.managed_redis[0].id
  depends_on  = [azapi_resource.managed_redis_database]
}

resource "azurerm_cosmosdb_account" "main" {
  name                = lower("${local.base_prefix}cdb")
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  offer_type = "Standard"
  kind       = "GlobalDocumentDB"

  consistency_policy { consistency_level = "Session" }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  public_network_access_enabled = false
}

resource "azurerm_search_service" "main" {
  name                = lower("${local.base_prefix}srch")
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  sku                           = "standard"
  partition_count               = 1
  replica_count                 = 1
  public_network_access_enabled = false
}
