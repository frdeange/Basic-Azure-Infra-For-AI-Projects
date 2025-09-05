#############################################
# 15-vpn-aad-apps.tf – AAD Apps for VPN (was aad-apps.tf)
#############################################

resource "random_uuid" "vpn_scope" { count = var.create_vpn_aad_apps ? 1 : 0 }

resource "azuread_application" "vpn_server" {
  count            = var.create_vpn_aad_apps ? 1 : 0
  display_name     = var.vpn_aad_server_app_display_name
  sign_in_audience = "AzureADMyOrg"

  api {
    requested_access_token_version = 2
    oauth2_permission_scope {
      admin_consent_description  = "Allow VPN clients to access the VPN gateway"
      admin_consent_display_name = "Access VPN"
      enabled                    = true
      id                         = random_uuid.vpn_scope[0].result
      type                       = "User"
      user_consent_description   = "Allow VPN client to connect"
      user_consent_display_name  = "Access VPN"
      value                      = var.vpn_aad_scope_name
    }
  }
}

resource "azuread_service_principal" "vpn_server" {
  count                        = var.create_vpn_aad_apps ? 1 : 0
  client_id                    = azuread_application.vpn_server[0].client_id
  app_role_assignment_required = false
}

resource "azuread_application" "vpn_client" {
  count                          = var.create_vpn_aad_apps ? 1 : 0
  display_name                   = var.vpn_aad_client_app_display_name
  sign_in_audience               = "AzureADMyOrg"
  fallback_public_client_enabled = true

  required_resource_access {
    resource_app_id = azuread_application.vpn_server[0].client_id
    resource_access {
      id   = tolist(azuread_application.vpn_server[0].api[0].oauth2_permission_scope)[0].id
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "vpn_client" {
  count     = var.create_vpn_aad_apps ? 1 : 0
  client_id = azuread_application.vpn_client[0].client_id
}
