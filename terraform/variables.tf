#############################################
# variables.tf
#############################################

variable "location" {
  type        = string
  description = "Azure region (e.g., westeurope)."
  default     = "westeurope"
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
  })
  description = "Subnet CIDR prefixes."
  default = {
    agw         = "10.10.0.0/24"
    privatelink = "10.10.1.0/24"
    apps        = "10.10.2.0/24"
    firewall    = "10.10.3.0/24"
    agent       = "10.10.4.0/24"
  }

  # Safer validation for parsers: avoid multiline &&, use alltrue list
  validation {
    condition = alltrue([
      can(cidrnetmask(var.subnet_prefixes.agw)),
      can(cidrnetmask(var.subnet_prefixes.privatelink)),
      can(cidrnetmask(var.subnet_prefixes.apps)),
      can(cidrnetmask(var.subnet_prefixes.firewall)),
      can(cidrnetmask(var.subnet_prefixes.agent))
    ])
    error_message = "All subnet_prefixes must be valid CIDR blocks."
  }
}
