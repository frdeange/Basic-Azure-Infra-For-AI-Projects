#############################################
# 04-data-services.tf – Data Storage and Search
#
# Redis Cache – Secure, Private, Persistent
#
# Semantic Caching Architecture for Azure OpenAI via APIM:
# --------------------------------------------------------
# This Redis Cache instance is used to store and retrieve semantic responses from Azure OpenAI, orchestrated by Azure API Management (APIM).
# - The cache is deployed in a private subnet with public access disabled and TLS 1.2 enforced.
# - APIM and OpenAI access Redis via Managed Identity and Private Endpoint only.
# - The cache supports data persistence and clustering for high availability.
#
# APIM Policy Example (XML):
# --------------------------
# <inbound>
#   <cache-lookup-value key="@(context.Request.Body.As<string>())" />
#   <choose>
#     <when condition="@(context.Cache.LookupValue != null)">
#       <return-response>
#         <set-body>@(context.Cache.LookupValue)</set-body>
#       </return-response>
#     </when>
#   </choose>
# </inbound>
# <backend>
#   <!-- Call Azure OpenAI backend -->
# </backend>
# <outbound>
#   <cache-store-value key="@(context.Request.Body.As<string>())" value="@(context.Response.Body.As<string>())" duration="300" />
# </outbound>
#
# This policy caches the response for each unique request body for 5 minutes (300 seconds).
# Ensure APIM is configured to use Redis as the cache backend and that network access is restricted to the VNET.
module "redis_cache" {
  source  = "claranet/redis/azurerm"
  version = "8.1.0"

  client_name                   = var.ai_prefix
  stack                         = var.stack
  environment                   = var.environment
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  location_short                = var.location_short
  logs_destinations_ids         = var.logs_destinations_ids
  subnet_id                     = azurerm_subnet.privatelink.id
  public_network_access_enabled = false
  minimum_tls_version           = "1.2"
  sku_name                      = var.redis_cache_sku
  capacity                      = var.redis_cache_capacity
  data_persistence_enabled      = var.redis_cache_persistence
  cluster_shard_count           = 3
  redis_version                 = 6
  extra_tags                    = var.redis_cache_tags
}

#############################################
# Cosmos DB (SQL API) – hardened
#############################################
resource "azurerm_cosmosdb_account" "main" {
  name                = lower("${var.ai_prefix}cosmosdb")
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

#############################################
# Azure AI Search – single replica (no HA)
#############################################
resource "azurerm_search_service" "main" {
  name                = lower("${var.ai_prefix}search")
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  sku                           = "standard"
  partition_count               = 1
  replica_count                 = 1
  public_network_access_enabled = false
}
