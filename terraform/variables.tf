# Public access control for Key Vault
variable "kv_public_access" {
  type        = bool
  default     = true
  description = "Enable or disable public access to Key Vault."
}


# Optional external PFX certificate (base64-encoded) for single-phase HTTPS deployment.
# If provided, it will be imported into Key Vault instead of generating a self-signed certificate.
variable "pfx_base64" {
  type        = string
  default     = ""
  description = "Base64-encoded PFX certificate to import into Key Vault (leave empty to auto-generate self-signed)."
}

variable "pfx_password" {
  type        = string
  default     = ""
  description = "Password for the provided PFX (ignored if pfx_base64 empty)."
  sensitive   = true
}

# Controls whether purge protection is enabled on Key Vault (default disabled to allow immediate re-creation in test environments)
variable "kv_purge_protection_enabled" {
  type        = bool
  default     = false
  description = "Enable purge protection on Key Vault (recommended true in production; false allows fast re-creation in test)."
}

variable "kv_allow_azure_services_bypass" {
  type        = bool
  default     = true
  description = "If true, network_acls.bypass includes AzureServices; set false to remove broad bypass once Private Endpoint is in place."
}
variable "kv_enabled_for_template_deployment" {
  type        = bool
  default     = true
  description = "Enable template deployment for Key Vault. Required for ARM deployments."
}

# Temporary bootstrap flag to allow public access for certificate creation (set true only during initial certificate provisioning then back to false)
variable "kv_certificate_bootstrap" {
  type        = bool
  default     = false
  description = "If true, temporarily enable Key Vault public network access to allow Terraform to create/import the initial certificate. Set back to false after first successful apply." 
}
# variables.tf

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID."
}

variable "location" {
  type        = string
  description = "Azure region (e.g., westeurope)."
  default     = "swedencentral"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the Resource Group."
  default     = "ai-baseline-rg"
}

variable "ai_prefix" {
  type        = string
  description = "Short, lowercase prefix for naming (3-10 chars)."
  default     = "aibaseln"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.ai_prefix))
    error_message = "ai_prefix must be 3-10 lowercase alphanumeric characters."
  }
  # Validación longitud storage: <ai_prefix> + 'stg' + optional suffix (5 por defecto, max 10) <= 24
  # Simplificada al caso peor (global_suffix_length máximo permitido 10)
  validation {
    condition     = length(var.ai_prefix) + 3 + (var.enable_global_suffix ? var.global_suffix_length : 0) <= 24
    error_message = "Nombre de storage excedería 24 caracteres (ajusta ai_prefix o global_suffix_length)."
  }
}

# Global random suffix controls (to avoid name collisions across parallel environments)
variable "enable_global_suffix" {
  type        = bool
  default     = true
  description = "If true, append a stable random suffix to resource names to guarantee global uniqueness (recommended for shared subscriptions)."
}

variable "global_suffix_length" {
  type        = number
  default     = 5
  description = "Length of the generated global random suffix (lowercase alphanumeric)."
  validation {
    condition     = var.global_suffix_length >= 3 && var.global_suffix_length <= 10
    error_message = "global_suffix_length must be between 3 and 10."
  }
}

variable "key_vault_name" {
  type        = string
  description = "Key Vault name (3-24 chars, lowercase letters, numbers, and hyphens)."
  default     = "aibaseln-kv"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 chars, start with a letter, end with letter/number, and use lowercase letters, numbers, or hyphens."
  }
}

variable "ai_services_name" {
  type        = string
  description = "Azure AI Services Hub name."
  default     = "aibaseln-ais" # abreviado
}

variable "ai_foundry_name" {
  type        = string
  description = "Azure AI Foundry (workspace/hub) name."
  default     = "aibaseln-aif" # abreviado
}

variable "ai_foundry_project_name" {
  type        = string
  description = "Azure AI Foundry Project name."
  default     = "aibaseln-project"
}

variable "redis_cache_name" {
  type        = string
  description = "Name for Redis Cache (3-24 chars, only letters, numbers, and hyphens)."
  default     = "aibaseln-redis"
}

variable "redis_cache_sku" {
  type        = string
  description = "Redis Cache SKU (Basic, Standard, Premium)."
  default     = "Premium"
}

variable "redis_cache_capacity" {
  type        = number
  description = "Redis Cache capacity (Premium: 1,2,3,4)."
  default     = 2
}

variable "redis_cache_persistence" {
  type        = bool
  description = "Enable data persistence in Redis Cache."
  default     = true
}

variable "redis_cache_tags" {
  type        = map(string)
  description = "Additional tags for Redis Cache."
  default     = {}
}

variable "stack" {
  type        = string
  description = "Stack/project name for Redis."
  default     = "ai-baseline"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, prod, etc.) for Redis."
  default     = "dev"
}

variable "location_short" {
  type        = string
  description = "Azure region abbreviation (e.g., weu, sc, etc.)."
  default     = "sc"
}

variable "logs_destinations_ids" {
  type        = list(string)
  description = "List of destination IDs for Redis logs (Storage, Log Analytics, Event Hub)."
  default     = []
}


variable "app_service_plan_sku" {
  type        = string
  description = "App Service Plan SKU (e.g., P1v3, P2v3, P3v3)."
  default     = "P1v3"

  validation {
    condition     = contains(["P1v3", "P2v3", "P3v3"], var.app_service_plan_sku)
    error_message = "Use one of: P1v3, P2v3, P3v3."
  }
}

variable "address_space" {
  type        = list(string)
  description = "VNet address space in CIDR blocks."
  default     = ["10.10.0.0/16"]

  validation {
    condition     = length([for cidr in var.address_space : cidr if can(cidrnetmask(cidr))]) == length(var.address_space)
    error_message = "address_space must contain valid CIDR blocks."
  }
}

variable "subnet_prefixes" {
  type = object({
    agw         = string
    privatelink = string
    apps        = string
    firewall    = string
    apim        = string
    agent       = optional(string)
    redis       = optional(string)
    bastion     = optional(string)
    jumpbox     = optional(string)
    gateway     = optional(string)
  })
  description = "Subnet CIDR prefixes."
  default = {
    agw         = "10.10.0.0/24"
    privatelink = "10.10.1.0/24"
    apps        = "10.10.2.0/24"
    firewall    = "10.10.3.0/24"
    agent       = "10.10.4.0/24"
    apim        = "10.10.5.0/24"
    bastion     = "10.10.6.0/26"
    jumpbox     = "10.10.6.64/27"
    gateway     = "10.10.6.96/27"
    redis       = "10.10.7.0/27"
  }

  # Safer validation for parsers: avoid multiline &&, use alltrue list
  validation {
    condition = alltrue([
      can(cidrnetmask(var.subnet_prefixes.agw)),
      can(cidrnetmask(var.subnet_prefixes.privatelink)),
      can(cidrnetmask(var.subnet_prefixes.apps)),
      can(cidrnetmask(var.subnet_prefixes.firewall)),
      can(cidrnetmask(var.subnet_prefixes.agent)),
      can(cidrnetmask(var.subnet_prefixes.apim)),
      var.subnet_prefixes.redis == null || can(cidrnetmask(var.subnet_prefixes.redis)),
      var.subnet_prefixes.bastion == null || can(cidrnetmask(var.subnet_prefixes.bastion)),
      var.subnet_prefixes.jumpbox == null || can(cidrnetmask(var.subnet_prefixes.jumpbox)),
      var.subnet_prefixes.gateway == null || can(cidrnetmask(var.subnet_prefixes.gateway))
    ])
    error_message = "All subnet_prefixes must be valid CIDR blocks."
  }
}

# Managed Redis (Azure Managed Redis via AzAPI preview)
variable "enable_managed_redis" {
  type        = bool
  default     = true
  description = "Enable deployment of Azure Managed Redis (redisEnterprise) via AzAPI preview."
}

variable "managed_redis_sku" {
  type        = string
  default     = "Balanced_B0"
  description = "SKU for Azure Managed Redis (e.g., Balanced_B0, Balanced_B1)."
}

variable "managed_redis_high_availability" {
  type        = bool
  default     = true
  description = "Enable high availability for Managed Redis cluster."
}

variable "managed_redis_eviction_policy" {
  type        = string
  default     = "NoEviction"
  description = "Eviction policy for the Managed Redis database (must be NoEviction when using RediSearch module)."
}

variable "managed_redis_clustering_policy" {
  type        = string
  default     = "EnterpriseCluster"
  description = "Clustering policy for Managed Redis (EnterpriseCluster or OSSCluster)."
}

variable "managed_redis_modules" {
  type        = list(string)
  default     = ["RedisJSON", "RediSearch"]
  description = "List of modules to enable on Managed Redis database."
}

variable "managed_redis_access_keys_auth_enabled" {
  type        = bool
  default     = true
  description = "Enable access keys authentication (if true sets accessKeysAuthentication=Enabled; false disables keys)."
}

variable "enable_managed_redis_private_endpoint" {
  type        = bool
  default     = true
  description = "Create Private Endpoint for Managed Redis (may fail if feature not available)."
}

variable "kv_hardening_enabled" {
  type        = bool
  default     = false
  description = "Cuando true, se espera cerrar acceso público al Key Vault (aplicado en fase posterior)."
}

# Remote access feature toggles
variable "enable_bastion" {
  type        = bool
  default     = true
  description = "Deploy Azure Bastion (recommended for secure remote access)."
}

variable "enable_jumpbox" {
  type        = bool
  default     = true
  description = "Deploy a Linux JumpBox VM for internal troubleshooting."
}

variable "enable_vpn_gateway" {
  type        = bool
  default     = false
  description = "Deploy a Point-to-Site VPN Gateway (adds cost and time)."
}

variable "jumpbox_admin_username" {
  type        = string
  default     = "azureuser"
  description = "Admin username for the JumpBox VM."
}

variable "jumpbox_ssh_public_key" {
  type        = string
  default     = ""
  description = "Optional SSH public key (if empty, Terraform will generate one using tls_private_key)."
}

variable "vpn_p2s_address_space" {
  type        = list(string)
  default     = ["172.16.250.0/24"]
  description = "Address pool for Point-to-Site VPN clients."
}

variable "vpn_root_cert_name" {
  type        = string
  default     = "p2s-root"
  description = "Name of the root certificate for P2S VPN (if using cert auth)."
}

variable "vpn_root_cert_data" {
  type        = string
  default     = ""
  description = "Base64-encoded root certificate public data (PEM without headers) for P2S. Leave empty to skip until provided."
}

# --- Azure AD (Entra ID) Point-to-Site VPN Authentication ---

variable "vpn_enable_aad" {
  type        = bool
  default     = false
  description = "Enable Azure AD (OpenVPN) authentication for P2S VPN (requires enable_vpn_gateway=true)."
}

variable "create_vpn_aad_apps" {
  type        = bool
  default     = false
  description = "Create Azure AD applications (server/client) automatically for VPN AAD auth."
}

variable "vpn_aad_scope_name" {
  type        = string
  default     = "VPN.Access"
  description = "OAuth2 permission scope name exposed by the VPN server application."
}

variable "vpn_aad_server_app_display_name" {
  type        = string
  default     = "vpn-p2s-server"
  description = "Display name for the server (resource) AAD application."
}

variable "vpn_aad_client_app_display_name" {
  type        = string
  default     = "vpn-p2s-client"
  description = "Display name for the client (public) AAD application."
}

variable "vpn_aad_server_app_id" {
  type        = string
  default     = ""
  description = "Existing Server App (Application) ID if not creating apps (leave empty when create_vpn_aad_apps=true)."
}

variable "vpn_aad_client_app_id" {
  type        = string
  default     = ""
  description = "Existing Client App (Application) ID if not creating apps (leave empty when create_vpn_aad_apps=true)."
}

variable "vpn_aad_audience" {
  type        = string
  default     = ""
  description = "Audience (Application ID / client_id) to use for AAD auth; if empty and apps created, uses generated server app client_id."
}

# --- Azure OpenAI (Cognitive Deployments) ---
variable "enable_openai_deployments" {
  type        = bool
  default     = true
  description = "Enable creation of Azure OpenAI (Cognitive) model deployments (chat + embeddings)."
}

variable "openai_chat_model_name" {
  type        = string
  default     = "gpt-4o-mini"
  description = "Model name for chat/completions deployment (Azure OpenAI)."
}

variable "openai_chat_model_version" {
  type        = string
  default     = "2024-07-18"
  description = "Model version for chat deployment (use specific version if pinning required)."
}

variable "openai_embeddings_model_name" {
  type        = string
  default     = "text-embedding-3-large"
  description = "Model name for embeddings deployment (Azure OpenAI)."
}

variable "openai_embeddings_model_version" {
  type        = string
  default     = "1"
  description = "Model version for embeddings deployment."
}

variable "openai_deployment_scale_type" {
  type        = string
  default     = "GlobalStandard"
  description = "Scale type for deployments (Standard or Manual depending on service capability)."
}

variable "openai_responses_model_name" {
  type        = string
  default     = "gpt-4.1-mini"
  description = "Model name for responses deployment (Azure OpenAI)."
}

variable "openai_responses_model_version" {
  type        = string
  default     = "2025-04-14"
  description = "Model version for responses deployment."
}

# --- Semantic Caching Configuration ---
variable "enable_semantic_cache" {
  type        = bool
  default     = true
  description = "Enable semantic caching for Azure OpenAI APIs (chat and responses)."
}

variable "semantic_cache_score_threshold" {
  type        = number
  default     = 0.8
  description = "Similarity score threshold for semantic cache hits (0.0-1.0)."
  validation {
    condition     = var.semantic_cache_score_threshold >= 0.0 && var.semantic_cache_score_threshold <= 1.0
    error_message = "Semantic cache score threshold must be between 0.0 and 1.0."
  }
}

variable "semantic_cache_duration_seconds" {
  type        = number
  default     = 60
  description = "Cache TTL duration for semantic cache entries in seconds."
}

variable "semantic_cache_max_message_count" {
  type        = number
  default     = 10
  description = "Maximum number of messages to consider for semantic similarity."
}

variable "semantic_cache_ignore_system_messages" {
  type        = bool
  default     = true
  description = "Ignore system messages when calculating semantic similarity."
}

# Manual override primary key for semantic cache (Redis). If empty, APIM Redis cache resource will be skipped to avoid empty connection string validation errors.
variable "semantic_cache_primary_key" {
  type        = string
  default     = ""
  description = "Primary access key for Managed Redis (semantic cache). Provide after initial deploy once key retrieved via portal/CLI to enable APIM Redis cache resource."
  sensitive   = true
}

# --- APIM OpenAI API Configuration ---
variable "openai_api_versions" {
  type = object({
    chat       = string
    responses  = string
    embeddings = string
  })
  default = {
    chat       = "2024-02-01"
    responses  = "2024-02-01"
    embeddings = "2024-02-01"
  }
  description = "API versions for different OpenAI operations."
}

# Terraform deployer object ID (for RBAC assignment to Key Vault)
variable "terraform_deployer_object_id" {
  type        = string
  description = "Object ID of the principal (user, service principal, or managed identity) running Terraform. Used for RBAC assignment to Key Vault."
  default     = ""
}

variable "openai_ab_testing" {
  type = object({
    chat_blue_deployment      = string
    chat_green_deployment     = string
    responses_blue_deployment = string
    responses_green_deployment = string
    chat_ab_percent          = number
    responses_ab_percent     = number
  })
  default = {
    chat_blue_deployment      = "chat"
    chat_green_deployment     = "chat"
    responses_blue_deployment = "responses"
    responses_green_deployment = "responses"
    chat_ab_percent          = 0
    responses_ab_percent     = 0
  }
  description = "A/B testing configuration for OpenAI deployments."
}
