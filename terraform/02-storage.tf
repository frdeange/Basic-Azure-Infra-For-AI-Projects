# 02-storage.tf – Storage and Key Management

# Storage Account (hardened)
resource "azurerm_storage_account" "main" {
  name                          = lower("${var.ai_prefix}storage")
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  account_tier                  = "Standard"
  account_replication_type      = "GRS"
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = false
}

# Key Vault (hardened) + Access Policy
resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                      = "standard"
  purge_protection_enabled      = var.kv_purge_protection_enabled
  public_network_access_enabled = var.kv_public_access

  network_acls {
    bypass                     = "AzureServices" # Allows trusted Azure services (certificate issuance, etc.) to access
    default_action             = var.kv_public_access ? "Allow" : "Deny"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }
}

# SSL certificate for Application Gateway (optional initial deploy)
resource "azurerm_key_vault_certificate" "ssl" {
  count        = var.deploy_certificate ? 1 : 0
  name         = "agw-ssl-cert"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault_access_policy.current_user]

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }
    key_properties {
      exportable = true
      key_type   = "RSA"
      key_size   = 2048
      reuse_key  = false
    }
    secret_properties {
      content_type = "application/x-pkcs12"
    }
    x509_certificate_properties {
      subject            = "CN=${var.ai_prefix}-agw"
      validity_in_months = 12
      key_usage          = ["digitalSignature", "keyEncipherment"]
    }
  }
}

resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions         = ["Create", "Get", "Delete", "Purge", "GetRotationPolicy"]
  secret_permissions      = ["Get", "List", "Set", "Delete", "Purge"]
  certificate_permissions = ["Get", "List", "Create", "Delete", "Purge", "Import", "Update", "ManageContacts", "ManageIssuers", "SetIssuers", "DeleteIssuers", "Get"]
}
