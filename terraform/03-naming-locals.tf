#############################################
# 03-naming-locals.tf – Naming helpers & shared locals
#############################################

# Stable random suffix applied to most resource names to avoid collisions.
resource "random_string" "global" {
  count   = var.enable_global_suffix ? 1 : 0
  length  = var.global_suffix_length
  upper   = false
  special = false
  numeric = true
  keepers = { ai_prefix = var.ai_prefix }
}

locals {
  global_suffix        = var.enable_global_suffix ? random_string.global[0].result : ""
  global_suffix_append = var.enable_global_suffix ? "-${random_string.global[0].result}" : ""
  base_prefix          = "${var.ai_prefix}${local.global_suffix_append}"

  private_dns_zones = [
    "privatelink.azurewebsites.net",
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.vaultcore.azure.net",
    "privatelink.documents.azure.com",
    "privatelink.search.windows.net",
    "privatelink.cognitiveservices.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.api.azureml.ms",
    "privatelink.redis.cache.windows.net"
  ]
}
