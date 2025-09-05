#############################################
# 08-ai-platform.tf – AI Services, Foundry, Project (was 03-ai-services.tf)
#############################################

resource "azurerm_ai_services" "main" {
  name                  = lower("${local.base_prefix}-ais")
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  sku_name              = "S0"
  custom_subdomain_name = lower("${local.base_prefix}-cog")
}

resource "azurerm_ai_foundry" "main" {
  name                = lower("${local.base_prefix}-aif")
  location            = azurerm_ai_services.main.location
  resource_group_name = azurerm_resource_group.main.name
  storage_account_id  = azurerm_storage_account.main.id
  key_vault_id        = azurerm_key_vault.main.id

  identity { type = "SystemAssigned" }
}

resource "azurerm_ai_foundry_project" "main" {
  name               = lower("${local.base_prefix}-aifprj")
  location           = azurerm_ai_foundry.main.location
  ai_services_hub_id = azurerm_ai_foundry.main.id

  identity { type = "SystemAssigned" }
}

# Azure OpenAI model deployments (native provider resources)
resource "azurerm_cognitive_deployment" "chat" {
  count           = var.enable_openai_deployments ? 1 : 0
  name            = "chat"
  cognitive_account_id = azurerm_ai_services.main.id
  rai_policy_name = "Microsoft.Default"

  model {
    format  = "OpenAI"
    name    = var.openai_chat_model_name
    version = var.openai_chat_model_version
  }

  sku {
    name = var.openai_deployment_scale_type
  }

  # Dynamic throttling not supported for GlobalStandard SKU; disabling.
  dynamic_throttling_enabled = false
}

resource "azurerm_cognitive_deployment" "responses" {
  count           = var.enable_openai_deployments ? 1 : 0
  name            = "responses"
  cognitive_account_id = azurerm_ai_services.main.id
  rai_policy_name = "Microsoft.Default"

  model {
    format  = "OpenAI"
    name    = var.openai_responses_model_name
    version = var.openai_responses_model_version
  }

  sku {
    name = var.openai_deployment_scale_type
  }

  # Dynamic throttling not supported for GlobalStandard SKU; disabling.
  dynamic_throttling_enabled = false
}

resource "azurerm_cognitive_deployment" "embeddings" {
  count           = var.enable_openai_deployments ? 1 : 0
  name            = "embeddings"
  cognitive_account_id = azurerm_ai_services.main.id
  rai_policy_name = "Microsoft.Default"

  model {
    format  = "OpenAI"
    name    = var.openai_embeddings_model_name
    version = var.openai_embeddings_model_version
  }

  sku {
    name = var.openai_deployment_scale_type
  }

  # Dynamic throttling not supported for GlobalStandard SKU; disabling.
  dynamic_throttling_enabled = false
}
