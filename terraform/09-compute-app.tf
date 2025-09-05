#############################################
# 09-compute-app.tf – App Service Plan, Web App, VNet integration (from 05-compute.tf)
#############################################

resource "azurerm_service_plan" "app" {
  name                = "${local.base_prefix}-asp"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
}

resource "azurerm_linux_web_app" "web" {
  name                = "${local.base_prefix}-web"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.app.id
  https_only          = true

  site_config {
    vnet_route_all_enabled = true
    minimum_tls_version    = "1.2"
    always_on              = true

    ip_restriction {
      name                      = "allow-agw"
      priority                  = 100
      action                    = "Allow"
      virtual_network_subnet_id = azurerm_subnet.agw.id
    }
    ip_restriction {
      name       = "deny-all"
      priority   = 200
      action     = "Deny"
      ip_address = "0.0.0.0/0"
    }
  }

  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE"              = "1"
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
  }

  identity { type = "SystemAssigned" }
}

resource "azurerm_app_service_virtual_network_swift_connection" "app_vnet" {
  app_service_id = azurerm_linux_web_app.web.id
  subnet_id      = azurerm_subnet.apps.id
}
