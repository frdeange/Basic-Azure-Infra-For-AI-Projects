# 05-compute.tf – Application Services

# App Service Plan + Web App (private)
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

# Application Gateway (WAF v2) in front of private Web App
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
  depends_on          = [null_resource.wait_for_kv_certificate]

  identity {
    type = "SystemAssigned"
  }

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
  # Optional HTTP port kept to redirect to HTTPS
  frontend_port {
    name = "http"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.agw.id
  }

  # Always attach SSL certificate from Key Vault (single-phase strategy)
  ssl_certificate {
    name                = "ssl-cert"
    key_vault_secret_id = azurerm_key_vault_certificate.ssl.secret_id
  }

  backend_address_pool {
    name = "webapp-pool"
  # AGW will resolve this FQDN to the private IP of the PE via Private DNS
  fqdns = [azurerm_linux_web_app.web.default_hostname]
  }

  # Placeholder: APIM internal backend (to be enabled after APIM Internal is provisioned and a private FQDN/IP decided)
  # APIM Internal backend (use gateway_url without scheme). Internal mode exposes a private FQDN resolvable only inside the VNet.
  backend_address_pool {
    name  = "apim-pool"
    fqdns = [replace(azurerm_api_management.main.gateway_url, "https://", "")]
  }

  backend_http_settings {
    name                                = "https"
    protocol                            = "Https"
    port                                = 443
    pick_host_name_from_backend_address = true
    request_timeout                     = 60
    cookie_based_affinity               = "Disabled"
  }

  # HTTP settings for APIM (host header will be picked from backend address FQDN)
  backend_http_settings {
    name                                = "apim-https"
    protocol                            = "Https"
    port                                = 443
    pick_host_name_from_backend_address = true
    request_timeout                     = 120
    cookie_based_affinity               = "Disabled"
  probe_name                          = "apim-probe"
  }

  # Probe for APIM (uses /status-0123456789abcdef to check gateway health)
  probe {
    name                = "apim-probe"
    protocol            = "Https"
    host                = replace(azurerm_api_management.main.gateway_url, "https://", "")
    path                = "/status-0123456789abcdef"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    match {
  status_code = ["200-399"]
    }
  }

  # Path-based rule to route /api/* to APIM and all other paths to the web app
  url_path_map {
    name                               = "apim-pathmap"
    default_backend_address_pool_name  = "webapp-pool"
    default_backend_http_settings_name = "https"

    path_rule {
      name                       = "apim-api"
      paths                      = ["/api/*"]
      backend_address_pool_name  = "apim-pool"
      backend_http_settings_name = "apim-https"
    }
  }

  # ...existing code...

  # HTTPS listener (primary)
  http_listener {
    name                           = "listener-https"
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "https"
    protocol                       = "Https"
    ssl_certificate_name           = "ssl-cert"
  }

  # Path-based routing rule (HTTPS)
  request_routing_rule {
    name               = "rule-https"
    rule_type          = "PathBasedRouting"
    http_listener_name = "listener-https"
    url_path_map_name  = "apim-pathmap"
    priority           = 100
  }

  # HTTP listener only to redirect all traffic to HTTPS
  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  redirect_configuration {
    name                 = "http-to-https"
    redirect_type        = "Permanent"
    target_listener_name = "listener-https"
    include_path         = true
    include_query_string = true
  }

  request_routing_rule {
    name               = "rule-http-redirect"
    rule_type          = "Basic"
    http_listener_name = "listener-http"
    redirect_configuration_name = "http-to-https"
    priority           = 90
  }

  firewall_policy_id = azurerm_web_application_firewall_policy.waf.id
}
