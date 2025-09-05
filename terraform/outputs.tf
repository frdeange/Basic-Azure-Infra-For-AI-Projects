# outputs.tf

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "application_gateway_public_ip" {
  value = azurerm_public_ip.agw.ip_address
}

output "webapp_default_hostname" {
  value = azurerm_linux_web_app.web.default_hostname
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "cosmosdb_account_name" {
  value = azurerm_cosmosdb_account.main.name
}

output "search_service_name" {
  value = azurerm_search_service.main.name
}

output "ai_services_name" {
  value = azurerm_ai_services.main.name
}

output "ai_foundry_name" {
  value = azurerm_ai_foundry.main.name
}

output "ai_foundry_project_name" {
  value = azurerm_ai_foundry_project.main.name
}

output "managed_redis_name" {
  description = "Azure Managed Redis (redisEnterprise) cluster name (if enabled)."
  value       = var.enable_managed_redis ? try(azapi_resource.managed_redis[0].name, null) : null
}

output "managed_redis_hostname" {
  description = "Azure Managed Redis hostname (if enabled)."
  value       = var.enable_managed_redis ? try(azapi_resource.managed_redis[0].output.properties.hostName, null) : null
}

# Remote Access Outputs (conditional)
output "bastion_public_ip" {
  description = "Bastion public IP address (if enabled)"
  value       = try(azurerm_public_ip.bastion[0].ip_address, null)
}

output "bastion_fqdn" {
  description = "Bastion FQDN (if enabled)"
  value       = try(azurerm_public_ip.bastion[0].fqdn, null)
}

output "jumpbox_private_ip" {
  description = "JumpBox private IP (if enabled)"
  value       = try(azurerm_network_interface.jumpbox[0].private_ip_address, null)
}

output "jumpbox_ssh_private_key_pem" {
  description = "Auto-generated SSH private key for the JumpBox (if no key was provided). Keep it secure."
  value       = try(tls_private_key.jumpbox[0].private_key_pem, null)
  sensitive   = true
}

output "vpn_gateway_public_ip" {
  description = "VPN Gateway public IP (if enabled)"
  value       = try(azurerm_public_ip.vpngw[0].ip_address, null)
}

output "vpn_gateway_name" {
  description = "VPN Gateway name (if enabled)"
  value       = try(azurerm_virtual_network_gateway.p2s[0].name, null)
}

output "vpn_gateway_id" {
  description = "VPN Gateway resource ID (if enabled)"
  value       = try(azurerm_virtual_network_gateway.p2s[0].id, null)
}

output "vpn_gateway_sku" {
  description = "VPN Gateway SKU (if enabled)"
  value       = try(azurerm_virtual_network_gateway.p2s[0].sku, null)
}

output "vpn_aad_scope_uuid" {
  description = "GUID of the OAuth2 permission scope on the server app (if apps created)"
  value       = var.create_vpn_aad_apps ? try(random_uuid.vpn_scope[0].result, null) : null
}

output "vpn_aad_scope_name" {
  description = "Name (value) of the OAuth2 scope used by VPN client"
  value       = var.vpn_aad_scope_name
}

# APIM Internal endpoints: In Internal mode there is no public IP; expose the name and internal gateway URL.
output "apim_name" {
  description = "APIM service name"
  value       = azurerm_api_management.main.name
}

output "apim_internal_gateway_url" {
  description = "Internal APIM gateway URL (requires internal DNS resolution)"
  value       = azurerm_api_management.main.gateway_url
}

# AAD VPN Outputs
output "vpn_aad_server_app_id" {
  description = "Server AAD Application (client_id) used as audience (if created)"
  value       = var.create_vpn_aad_apps ? try(azuread_application.vpn_server[0].client_id, null) : var.vpn_aad_server_app_id
}

output "vpn_aad_client_app_id" {
  description = "Client AAD Application (if created)"
  value       = var.create_vpn_aad_apps ? try(azuread_application.vpn_client[0].client_id, null) : var.vpn_aad_client_app_id
}

output "vpn_aad_audience_effective" {
  description = "Effective audience used by VPN gateway for AAD auth"
  value       = var.vpn_enable_aad ? (coalesce(var.vpn_aad_audience, (var.create_vpn_aad_apps ? try(azuread_application.vpn_server[0].client_id, "") : var.vpn_aad_server_app_id))) : null
}

output "vpn_client_protocols_effective" {
  description = "List of VPN client protocols enabled (depends on AAD setting)"
  value       = var.enable_vpn_gateway ? (var.vpn_enable_aad ? ["OpenVPN"] : ["OpenVPN", "IkeV2"]) : []
}

# OpenAI API and Semantic Caching Outputs
output "openai_api_gateway_url" {
  description = "OpenAI API gateway URL through APIM (requires internal access or AGW routing)"
  value       = "${azurerm_api_management.main.gateway_url}/openai"
}

output "openai_chat_endpoint" {
  description = "Chat completions endpoint with semantic caching and A/B testing"
  value       = "${azurerm_api_management.main.gateway_url}/openai/chat"
}

output "openai_responses_endpoint" {
  description = "Response generation endpoint with semantic caching and A/B testing"
  value       = "${azurerm_api_management.main.gateway_url}/openai/response"
}

output "openai_embeddings_endpoint" {
  description = "Embeddings endpoint (no semantic caching, direct routing)"
  value       = "${azurerm_api_management.main.gateway_url}/openai/embeddings"
}

output "semantic_cache_enabled" {
  description = "Whether semantic caching is enabled"
  value       = var.enable_semantic_cache
}

output "semantic_cache_redis_connection" {
  description = "Redis cache connection status for semantic caching"
  value       = var.enable_semantic_cache ? "Configured with Azure Managed Redis Enterprise" : "Disabled"
}

output "openai_deployments_config" {
  description = "Summary of OpenAI deployments configured"
  value = {
    chat_model        = var.openai_chat_model_name
    chat_version      = var.openai_chat_model_version
    responses_model   = var.openai_responses_model_name
    responses_version = var.openai_responses_model_version
    embeddings_model  = var.openai_embeddings_model_name
    embeddings_version = var.openai_embeddings_model_version
  }
}

output "ab_testing_config" {
  description = "A/B testing configuration for OpenAI deployments"
  value = var.enable_semantic_cache ? {
    chat_blue_deployment     = var.openai_ab_testing.chat_blue_deployment
    chat_green_deployment    = var.openai_ab_testing.chat_green_deployment
    chat_ab_percent          = var.openai_ab_testing.chat_ab_percent
    responses_blue_deployment = var.openai_ab_testing.responses_blue_deployment
    responses_green_deployment = var.openai_ab_testing.responses_green_deployment
    responses_ab_percent     = var.openai_ab_testing.responses_ab_percent
    enabled                  = true
  } : {
    enabled = false
    message = "A/B testing disabled (semantic cache disabled)"
  }
}

# --- Debug Outputs (temporary for redisEnterprise AzAPI data shape introspection) ---
output "redis_access_keys_raw" {
  value       = try(data.azapi_resource_action.redis_access_keys[0].output, null)
  description = "Raw output from redisEnterprise listKeys action (debug)."
  sensitive   = true
}

output "redis_primary_raw" {
  value       = try(data.azapi_resource.redis_primary[0].output, null)
  description = "Raw redisEnterprise primary resource output (debug)."
  sensitive   = true
}

