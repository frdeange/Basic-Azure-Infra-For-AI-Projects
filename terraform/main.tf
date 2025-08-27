#############################################
# main.tf – Azure AI Foundry Baseline (Secure)
#############################################

#############################################
# Client context
#############################################
data "azurerm_client_config" "current" {}

#############################################
# Resource Group (single)
#############################################
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}
