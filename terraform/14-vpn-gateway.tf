#############################################
# 14-vpn-gateway.tf – VPN Gateway (from 10-remote-access.tf)
#############################################

resource "azurerm_public_ip" "vpngw" {
  count               = var.enable_vpn_gateway ? 1 : 0
  name                = "${var.ai_prefix}-vpngw-pip${local.global_suffix_append}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_virtual_network_gateway" "p2s" {
  count               = var.enable_vpn_gateway ? 1 : 0
  name                = "${var.ai_prefix}-vpngw${local.global_suffix_append}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = false
  enable_bgp          = false
  sku                 = "VpnGw1"

  ip_configuration {
    name                          = "vpngw"
    public_ip_address_id          = azurerm_public_ip.vpngw[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway[0].id
  }

  vpn_client_configuration {
    address_space        = var.vpn_p2s_address_space
    vpn_client_protocols = var.vpn_enable_aad ? ["OpenVPN"] : (var.vpn_root_cert_data != "" ? ["OpenVPN", "IkeV2"] : ["OpenVPN"])

    dynamic "root_certificate" {
      for_each = (!var.vpn_enable_aad && var.vpn_root_cert_data != "") ? [1] : []
      content {
        name             = var.vpn_root_cert_name
        public_cert_data = var.vpn_root_cert_data
      }
    }

    aad_tenant   = var.vpn_enable_aad ? "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/" : null
    aad_issuer   = var.vpn_enable_aad ? "https://sts.windows.net/${data.azurerm_client_config.current.tenant_id}/" : null
    aad_audience = var.vpn_enable_aad ? coalesce(var.vpn_aad_audience, (var.create_vpn_aad_apps ? azuread_application.vpn_server[0].client_id : var.vpn_aad_server_app_id)) : null
  }
}
