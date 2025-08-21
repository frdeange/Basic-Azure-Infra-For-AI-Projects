#############################################
# main.tf – Azure AI Foundry Baseline (Secure)
#############################################

#############################################
# Client context
#############################################
data "azurerm_client_config" "current" {}

#############################################
# Resource Group (single)
#############################################
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

#############################################
# Core Networking (VNet + Subnets)
#############################################
resource "azurerm_virtual_network" "main" {
  name                = "${var.ai_prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.address_space
}

# Application Gateway subnet (required)
resource "azurerm_subnet" "agw" {
  name                 = "snet-agw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_prefixes.agw]
}

# Private Endpoints subnet (v4: string flag)
resource "azurerm_subnet" "privatelink" {
  name                              = "snet-privatelink"
  resource_group_name               = azurerm_resource_group.main.name
  virtual_network_name              = azurerm_virtual_network.main.name
  address_prefixes                  = [var.subnet_prefixes.privatelink]
  private_endpoint_network_policies = "Disabled"
}

# App Service VNet Integration subnet (delegated)
resource "azurerm_subnet" "apps" {
  name                 = "snet-apps"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_prefixes.apps]
  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Azure Firewall subnet (reserved name)
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_prefixes.firewall]
}

# Agent subnet (egress via Azure Firewall)
resource "azurerm_subnet" "agent" {
  name                 = "snet-agent"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_prefixes.agent]
}

#############################################
# Private DNS Zones (linked to VNet)
#############################################
locals {
  private_dns_zones = [
    "privatelink.azurewebsites.net",           # App Service
    "privatelink.blob.core.windows.net",       # Storage (Blob)
    "privatelink.file.core.windows.net",       # Storage (File)
    "privatelink.vaultcore.azure.net",         # Key Vault
    "privatelink.documents.azure.com",         # Cosmos DB
    "privatelink.search.windows.net",          # Azure AI Search
    "privatelink.cognitiveservices.azure.com", # Azure AI Services
    "privatelink.openai.azure.com",            # Azure OpenAI (optional)
    "privatelink.api.azureml.ms"               # Azure AI Foundry / AML workspace
  ]
}

resource "azurerm_private_dns_zone" "zones" {
  for_each            = toset(local.private_dns_zones)
  name                = each.value
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = azurerm_private_dns_zone.zones
  name                  = "link-${replace(each.key, ".", "-")}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
}

#############################################
# Storage Account (hardened)
#############################################
resource "azurerm_storage_account" "main" {
  name                          = lower("${var.ai_prefix}storage")
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  account_tier                  = "Standard"
  account_replication_type      = "GRS"
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = false
}

#############################################
# Key Vault (hardened) + Access Policy
#############################################
resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                      = "standard"
  purge_protection_enabled      = true
  public_network_access_enabled = false
}

resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions         = ["Create", "Get", "Delete", "Purge", "GetRotationPolicy"]
  secret_permissions      = ["Get", "List", "Set", "Delete", "Purge"]
  certificate_permissions = ["Get", "List"]
}

#############################################
# Azure AI Services Hub + Foundry + Project
#############################################
resource "azurerm_ai_services" "main" {
  name                = lower(var.ai_services_name)
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "S0"
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
}

# RBAC: Foundry to Storage + Key Vault
resource "azurerm_role_assignment" "foundry_storage_contrib" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_ai_foundry.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "foundry_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_ai_foundry.main.identity[0].principal_id
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

#############################################
# Private Endpoints (+ Private DNS Zone Groups)
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

#############################################
# App Service Plan + Linux Web App (private)
#############################################
resource "azurerm_service_plan" "app" {
  name                = "${var.ai_prefix}-asp"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
}

resource "azurerm_linux_web_app" "web" {
  name                = "${var.ai_prefix}-web"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.app.id
  https_only          = true

  site_config {
    vnet_route_all_enabled = true
    minimum_tls_version    = "1.2"
    always_on              = true
  }

  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE"              = "1"
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
  }

  identity {
    type = "SystemAssigned"
  }
}

# VNet Integration (outbound from Web App)
resource "azurerm_app_service_virtual_network_swift_connection" "app_vnet" {
  app_service_id = azurerm_linux_web_app.web.id
  subnet_id      = azurerm_subnet.apps.id
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

#############################################
# Application Gateway (WAF v2) in front of private Web App
#############################################
resource "azurerm_public_ip" "agw" {
  name                = "${var.ai_prefix}-agw-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_web_application_firewall_policy" "waf" {
  name                = "${var.ai_prefix}-wafpol"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  policy_settings {
    enabled = true
    mode    = "Prevention"
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}

resource "azurerm_application_gateway" "main" {
  name                = "${var.ai_prefix}-agw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gwipc"
    subnet_id = azurerm_subnet.agw.id
  }

  frontend_port {
    name = "https"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.agw.id
  }

  backend_address_pool {
    name = "webapp-pool"
    # AGW resolverá este FQDN a la IP privada del PE vía Private DNS
    fqdns = [azurerm_linux_web_app.web.default_hostname]
  }

  backend_http_settings {
    name                                = "https"
    protocol                            = "Https"
    port                                = 443
    pick_host_name_from_backend_address = true
    request_timeout                     = 60
    cookie_based_affinity               = "Disabled"
  }

  http_listener {
    name                           = "listener-https"
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "https"
    protocol                       = "Https"
    # Añade aquí el certificado SSL para producción si corresponde
    # ssl_certificate_name = azurerm_application_gateway_certificate.cert.name
  }

  request_routing_rule {
    name                       = "rule1"
    rule_type                  = "Basic"
    http_listener_name         = "listener-https"
    backend_address_pool_name  = "webapp-pool"
    backend_http_settings_name = "https"
    priority                   = 100
  }

  firewall_policy_id = azurerm_web_application_firewall_policy.waf.id
}

#############################################
# Azure Firewall + Egress UDR (for Agent subnet)
#############################################
resource "azurerm_public_ip" "afw" {
  name                = "${var.ai_prefix}-afw-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "main" {
  name                = "${var.ai_prefix}-afw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.afw.id
  }
}

resource "azurerm_route_table" "agent_udr" {
  name                = "${var.ai_prefix}-rt-agent"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "agent_udr_assoc" {
  subnet_id      = azurerm_subnet.agent.id
  route_table_id = azurerm_route_table.agent_udr.id
}

#############################################
# Observability: Log Analytics + Application Insights
#############################################
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.ai_prefix}-law"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "main" {
  name                = "${var.ai_prefix}-appi"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main.id
}

