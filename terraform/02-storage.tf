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

# SSL certificate strategy (single-phase):
# If an external PFX (base64) is provided, import it via azurerm_key_vault_certificate using the "Import" action.
# Otherwise, create a self-signed certificate so HTTPS is available on first apply.
locals {
  use_imported_pfx = length(trimspace(var.pfx_base64)) > 0
}

resource "azurerm_key_vault_certificate" "ssl" {
  name         = "agw-ssl-cert"
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_key_vault_access_policy.current_user]

  certificate_policy {
    issuer_parameters {
      name = local.use_imported_pfx ? "Unknown" : "Self"
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

  # Import action only when external PFX provided
  dynamic "certificate" {
    for_each = local.use_imported_pfx ? [1] : []
    content {
      contents = var.pfx_base64
      password = var.pfx_password
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

# Access policy for Application Gateway managed identity to retrieve certificate secret
resource "azurerm_key_vault_access_policy" "agw" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_application_gateway.main.identity[0].principal_id

  secret_permissions      = ["Get", "List"]
  certificate_permissions = ["Get", "List"]
}

# Small wait to reduce risk of eventual consistency issues before AGW reads secret
resource "null_resource" "wait_for_kv_certificate" {
  triggers = {
    cert_version = azurerm_key_vault_certificate.ssl.version
  }
  provisioner "local-exec" {
    command = "sleep 30"
  }
}
