#############################################
# locals.tf – Shared Local Variables
#############################################

locals {
  private_dns_zones = [
    "privatelink.azurewebsites.net",           # App Service
    "privatelink.blob.core.windows.net",       # Storage (Blob)
    "privatelink.file.core.windows.net",       # Storage (File)
    "privatelink.vaultcore.azure.net",         # Key Vault
    "privatelink.documents.azure.com",         # Cosmos DB
    "privatelink.search.windows.net",          # Azure AI Search
    "privatelink.cognitiveservices.azure.com", # Azure AI Services
    "privatelink.openai.azure.com",            # Azure OpenAI (optional)
    "privatelink.api.azureml.ms",              # Azure AI Foundry / AML workspace
    "privatelink.redis.cache.windows.net"      # Azure Redis Cache
  ]
}
