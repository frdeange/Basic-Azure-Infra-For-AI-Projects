# Public access control for Key Vault
variable "kv_public_access" {
  type        = bool
  default     = true
  description = "Enable or disable public access to Key Vault."
}

variable "deploy_certificate" {
  type        = bool
  default     = false
  description = "Whether to deploy the Application Gateway SSL certificate in Key Vault on initial build."
}

# Controls whether purge protection is enabled on Key Vault (default disabled to allow immediate re-creation in test environments)
variable "kv_purge_protection_enabled" {
  type        = bool
  default     = false
  description = "Enable purge protection on Key Vault (recommended true in production; false allows fast re-creation in test)."
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
  default     = "aibaseln-aisvc"
}

variable "ai_foundry_name" {
  type        = string
  description = "Azure AI Foundry (workspace/hub) name."
  default     = "aibaseln-foundry"
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
    agent       = string
    apim        = string
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
      var.subnet_prefixes.bastion == null || can(cidrnetmask(var.subnet_prefixes.bastion)),
      var.subnet_prefixes.jumpbox == null || can(cidrnetmask(var.subnet_prefixes.jumpbox)),
      var.subnet_prefixes.gateway == null || can(cidrnetmask(var.subnet_prefixes.gateway))
    ])
    error_message = "All subnet_prefixes must be valid CIDR blocks."
  }
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
