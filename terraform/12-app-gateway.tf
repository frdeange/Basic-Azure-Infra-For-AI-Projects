#############################################
# 12-app-gateway.tf – WAF Policy, UAI, Application Gateway (split from 05-compute.tf)
#############################################

resource "azurerm_web_application_firewall_policy" "waf" {
  name                = "${local.base_prefix}-wafpol"
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

resource "azurerm_user_assigned_identity" "agw" {
  name                = "${local.base_prefix}-agw-identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

resource "azurerm_public_ip" "agw" {
  name                = "${local.base_prefix}-agw-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "main" {
  name                = "${local.base_prefix}-agw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  depends_on = [
    azurerm_role_assignment.agw_kv_cert_reader,
    azurerm_role_assignment.agw_kv_secret_reader,
    azurerm_key_vault_certificate.ssl
  ]
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agw.id]
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
  frontend_port {
    name = "http"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.agw.id
  }

  ssl_certificate {
    name                = "ssl-cert"
    key_vault_secret_id = azurerm_key_vault_certificate.ssl.secret_id
  }

  backend_address_pool {
    name  = "webapp-pool"
    fqdns = [azurerm_linux_web_app.web.default_hostname]
  }
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

  backend_http_settings {
    name                                = "apim-https"
    protocol                            = "Https"
    port                                = 443
    pick_host_name_from_backend_address = true
    request_timeout                     = 120
    cookie_based_affinity               = "Disabled"
    probe_name                          = "apim-probe"
  }

  probe {
    name                = "apim-probe"
    protocol            = "Https"
    host                = replace(azurerm_api_management.main.gateway_url, "https://", "")
    path                = "/status-0123456789abcdef"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    match { status_code = ["200-399"] }
  }

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

  http_listener {
    name                           = "listener-https"
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "https"
    protocol                       = "Https"
    ssl_certificate_name           = "ssl-cert"
  }

  request_routing_rule {
    name               = "rule-https"
    rule_type          = "PathBasedRouting"
    http_listener_name = "listener-https"
    url_path_map_name  = "apim-pathmap"
    priority           = 100
  }

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
    name                        = "rule-http-redirect"
    rule_type                   = "Basic"
    http_listener_name          = "listener-http"
    redirect_configuration_name = "http-to-https"
    priority                    = 90
  }

  firewall_policy_id = azurerm_web_application_firewall_policy.waf.id
}
