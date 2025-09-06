#############################################
# 06-storage-keyvault.tf – Storage Account & Key Vault (was 02-storage.tf)
#############################################

resource "azurerm_storage_account" "main" {
  # nombre abreviado: <ai_prefix>stg<suffix>
  name                          = lower(replace("${var.ai_prefix}stg${local.global_suffix}", "--", "-"))
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  account_tier                  = "Standard"
  account_replication_type      = "GRS"
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = false
  # Hardened flags (were drifting to true in plan due to provider defaults if unspecified)
  shared_access_key_enabled     = false
  allow_nested_items_to_be_public = false
}

resource "random_string" "kv_suffix" {
  length  = 5
  upper   = false
  special = false
  numeric = true
}

locals {
  effective_kv_name = var.key_vault_name == "aibaseln-kv" ? substr(replace("${var.ai_prefix}-kv-${random_string.kv_suffix.result}", "--", "-"), 0, 24) : var.key_vault_name
  use_imported_pfx  = length(trimspace(var.pfx_base64)) > 0
}

resource "azurerm_key_vault" "main" {
  name                = local.effective_kv_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                       = "standard"
  purge_protection_enabled       = var.kv_purge_protection_enabled
  # Secure by default; optionally relaxed during first certificate provisioning if kv_certificate_bootstrap = true
  # Public network only enabled during bootstrap phase; hardened phase disables it
  public_network_access_enabled  = var.kv_certificate_bootstrap ? true : false
  # rbac_authorization_enabled     = true
  # Only enable for template deployment during bootstrap to satisfy certificate creation then disable when hardened
  # Keep enabled for template deployment so Terraform can manage certificate resource during hardening
  enabled_for_template_deployment = true
  soft_delete_retention_days     = 7
  network_acls {
  # During bootstrap we allow AzureServices for template deployment convenience; afterwards remove bypass (None)
  # Always allow trusted Azure services (includes Application Gateway) to retrieve secrets
  bypass         = "AzureServices"
    # During bootstrap open firewall (Allow) to simplify certificate issuance, Deny afterwards
    default_action = var.kv_certificate_bootstrap ? "Allow" : "Deny"
    ip_rules       = []
    virtual_network_subnet_ids = []
  }
}

resource "azurerm_key_vault_certificate" "ssl" {
  name         = "agw-ssl-cert"
  key_vault_id = azurerm_key_vault.main.id
  # Deployer must have certificate permissions (assumed pre-granted); explicit depends_on removed after RBAC simplification

  certificate_policy {
    issuer_parameters { name = local.use_imported_pfx ? "Unknown" : "Self" }
    key_properties {
      exportable = true
      key_type   = "RSA"
      key_size   = 2048
      reuse_key  = false
    }
    secret_properties { content_type = "application/x-pkcs12" }
    x509_certificate_properties {
      subject            = "CN=${local.base_prefix}-agw"
      validity_in_months = 12
      key_usage          = ["digitalSignature", "keyEncipherment"]
    }
  }

  dynamic "certificate" {
    for_each = local.use_imported_pfx ? [1] : []
    content {
      contents = var.pfx_base64
      password = var.pfx_password
    }
  }
}

resource "null_resource" "wait_for_kv_certificate" {
  triggers = { cert_version = azurerm_key_vault_certificate.ssl.version }
  provisioner "local-exec" { command = "sleep 30" }
}
