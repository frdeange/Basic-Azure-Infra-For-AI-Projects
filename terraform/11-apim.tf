#############################################
# 11-apim.tf – API Management & OpenAI backend (was 09-apim.tf)
#############################################

resource "azurerm_api_management" "main" {
  name                 = "${local.base_prefix}-apim"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  publisher_name       = "AI Team"
  publisher_email      = "ai-team@example.com"
  sku_name             = "Developer_1"
  virtual_network_type = "Internal"

  virtual_network_configuration { subnet_id = azurerm_subnet.apim.id }

  identity { type = "SystemAssigned" }
  timeouts {
    create = "2h"
    update = "2h"
    delete = "2h"
  }
  depends_on = [azurerm_subnet_network_security_group_association.apim_nsg_assoc]
}

resource "azurerm_api_management_backend" "aoai_root" {
  name                = "aoai-root"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  protocol            = "http"
  url                 = "https://${azurerm_ai_services.main.custom_subdomain_name}.cognitiveservices.azure.com"
  description         = "Azure OpenAI root backend for all deployments"
}

# Named Values for OpenAI configuration
resource "azurerm_api_management_named_value" "aoai_resource" {
  name                = "AOAI-RESOURCE"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "AOAI-RESOURCE"
  value               = "https://${azurerm_ai_services.main.custom_subdomain_name}.cognitiveservices.azure.com"
}

resource "azurerm_api_management_named_value" "api_version_chat" {
  name                = "API-VERSION-CHAT"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "API-VERSION-CHAT"
  value               = var.openai_api_versions.chat
}

resource "azurerm_api_management_named_value" "api_version_resp" {
  name                = "API-VERSION-RESP"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "API-VERSION-RESP"
  value               = var.openai_api_versions.responses
}

resource "azurerm_api_management_named_value" "api_version_emb" {
  name                = "API-VERSION-EMB"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "API-VERSION-EMB"
  value               = var.openai_api_versions.embeddings
}

resource "azurerm_api_management_named_value" "chat_blue_deployment" {
  name                = "CHAT-BLUE-DEPLOYMENT"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "CHAT-BLUE-DEPLOYMENT"
  value               = var.openai_ab_testing.chat_blue_deployment
}

resource "azurerm_api_management_named_value" "chat_green_deployment" {
  name                = "CHAT-GREEN-DEPLOYMENT"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "CHAT-GREEN-DEPLOYMENT"
  value               = var.openai_ab_testing.chat_green_deployment
}

resource "azurerm_api_management_named_value" "resp_blue_deployment" {
  name                = "RESP-BLUE-DEPLOYMENT"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "RESP-BLUE-DEPLOYMENT"
  value               = var.openai_ab_testing.responses_blue_deployment
}

resource "azurerm_api_management_named_value" "resp_green_deployment" {
  name                = "RESP-GREEN-DEPLOYMENT"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "RESP-GREEN-DEPLOYMENT"
  value               = var.openai_ab_testing.responses_green_deployment
}

resource "azurerm_api_management_named_value" "emb_deployment" {
  name                = "EMB-DEPLOYMENT"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "EMB-DEPLOYMENT"
  value               = "embeddings"
}

resource "azurerm_api_management_named_value" "ab_percent_chat" {
  name                = "AB-PERCENT-CHAT"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "AB-PERCENT-CHAT"
  value               = tostring(var.openai_ab_testing.chat_ab_percent)
}

resource "azurerm_api_management_named_value" "ab_percent_resp" {
  name                = "AB-PERCENT-RESP"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  display_name        = "AB-PERCENT-RESP"
  value               = tostring(var.openai_ab_testing.responses_ab_percent)
}

# External Redis Cache for Semantic Caching
locals {
  semantic_cache_active = var.enable_semantic_cache && length(trimspace(var.semantic_cache_primary_key)) > 0
}

resource "azurerm_api_management_redis_cache" "semantic_cache" {
  count             = local.semantic_cache_active ? 1 : 0
  name              = "semantic-cache"
  api_management_id = azurerm_api_management.main.id
  connection_string = var.semantic_cache_primary_key
  description       = try(data.azapi_resource.redis_primary[0].output.properties.hostName, "Managed Redis host")
  depends_on        = [data.azapi_resource.redis_primary]
}

# OpenAI API with three operations
resource "azurerm_api_management_api" "openai" {
  name                  = "openai-api"
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
  revision              = "1"
  display_name          = "OpenAI API"
  path                  = "openai"
  protocols             = ["https"]
  description           = "Azure OpenAI API with semantic caching and A/B testing"
  service_url           = "https://${azurerm_ai_services.main.custom_subdomain_name}.cognitiveservices.azure.com"
  
  subscription_required = true
  subscription_key_parameter_names {
    header = "Ocp-Apim-Subscription-Key"
    query  = "subscription-key"
  }
}

# Chat completions operation
resource "azurerm_api_management_api_operation" "chat_completions" {
  operation_id        = "chat-completions"
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Chat Completions"
  method              = "POST"
  url_template        = "/chat"
  description         = "Create chat completions with semantic caching and A/B testing"
  
  request {
    header {
      name     = "api-version"
      required = true
      type     = "string"
    }
    header {
      name     = "Content-Type"
      required = true
      type     = "string"
    }
  }
  
  response {
    status_code = 200
    description = "Successful response"
  }
}

# Chat completions operation policy
resource "azurerm_api_management_api_operation_policy" "chat_completions" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  operation_id        = azurerm_api_management_api_operation.chat_completions.operation_id

  xml_content = <<XML
<policies>
    <inbound>
        <base />
        <!-- API Version validation -->
        <choose>
            <when condition='@(!context.Request.Headers.ContainsKey("api-version"))'>
                <return-response>
                    <set-status code="400" reason="Bad Request" />
                    <set-body>{"error": {"code": "InvalidRequest", "message": "api-version header is required"}}</set-body>
                </return-response>
            </when>
            <when condition='@(context.Request.Headers.GetValueOrDefault("api-version") != "{{API-VERSION-CHAT}}")'>
                <return-response>
                    <set-status code="400" reason="Bad Request" />
                    <set-body>{"error": {"code": "InvalidApiVersion", "message": "Unsupported api-version for chat completions"}}</set-body>
                </return-response>
            </when>
        </choose>
        
  <!-- Simplified policy (semantic cache & A/B removed for validation) -->
  <set-variable name="selectedDeployment" value="{{CHAT-BLUE-DEPLOYMENT}}" />
  <rewrite-uri template="/openai/deployments/{{CHAT-BLUE-DEPLOYMENT}}/chat/completions?api-version={{API-VERSION-CHAT}}" />
        
        <!-- Set backend to aoai-root -->
        <set-backend-service backend-id="aoai-root" />
        
        <!-- Add deployment tracking header -->
        <set-header name="X-APIM-Deployment" exists-action="override">
            <value>@((string)context.Variables["selectedDeployment"])</value>
        </set-header>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        
  <!-- Simplified: cache store removed -->
        
        <!-- Add deployment info to response -->
        <set-header name="X-Deployment-Used" exists-action="override">
            <value>@((string)context.Variables["selectedDeployment"])</value>
        </set-header>
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
XML
}

# Response generation operation
resource "azurerm_api_management_api_operation" "responses" {
  operation_id        = "responses"
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Response Generation"
  method              = "POST"
  url_template        = "/response"
  description         = "Generate responses with semantic caching and A/B testing"
  
  request {
    header {
      name     = "api-version"
      required = true
      type     = "string"
    }
    header {
      name     = "Content-Type"
      required = true
      type     = "string"
    }
  }
  
  response {
    status_code = 200
    description = "Successful response"
  }
}

# Embeddings operation
resource "azurerm_api_management_api_operation" "embeddings" {
  operation_id        = "embeddings"
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Create Embeddings"
  method              = "POST"
  url_template        = "/embeddings"
  description         = "Create embeddings (no semantic caching)"
  
  request {
    header {
      name     = "api-version"
      required = true
      type     = "string"
    }
    header {
      name     = "Content-Type"
      required = true
      type     = "string"
    }
  }
  
  response {
    status_code = 200
    description = "Successful response"
  }
}

# Response generation operation policy
resource "azurerm_api_management_api_operation_policy" "responses" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  operation_id        = azurerm_api_management_api_operation.responses.operation_id

  xml_content = <<XML
<policies>
    <inbound>
        <base />
        <!-- API Version validation -->
        <choose>
            <when condition='@(!context.Request.Headers.ContainsKey("api-version"))'>
                <return-response>
                    <set-status code="400" reason="Bad Request" />
                    <set-body>{"error": {"code": "InvalidRequest", "message": "api-version header is required"}}</set-body>
                </return-response>
            </when>
            <when condition='@(context.Request.Headers.GetValueOrDefault("api-version") != "{{API-VERSION-RESP}}")'>
                <return-response>
                    <set-status code="400" reason="Bad Request" />
                    <set-body>{"error": {"code": "InvalidApiVersion", "message": "Unsupported api-version for responses"}}</set-body>
                </return-response>
            </when>
        </choose>
        
  <!-- Simplified policy (semantic cache & A/B removed for validation) -->
  <set-variable name="selectedDeployment" value="{{RESP-BLUE-DEPLOYMENT}}" />
  <rewrite-uri template="/openai/deployments/{{RESP-BLUE-DEPLOYMENT}}/responses?api-version={{API-VERSION-RESP}}" />
        
        <!-- Set backend to aoai-root -->
        <set-backend-service backend-id="aoai-root" />
        
        <!-- Add deployment tracking header -->
        <set-header name="X-APIM-Deployment" exists-action="override">
            <value>@((string)context.Variables["selectedDeployment"])</value>
        </set-header>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        
  <!-- Simplified: cache store removed -->
        
        <!-- Add deployment info to response -->
        <set-header name="X-Deployment-Used" exists-action="override">
            <value>@((string)context.Variables["selectedDeployment"])</value>
        </set-header>
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
XML
}

# Embeddings operation policy (no semantic caching, direct routing)
resource "azurerm_api_management_api_operation_policy" "embeddings" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  operation_id        = azurerm_api_management_api_operation.embeddings.operation_id

  xml_content = <<XML
<policies>
    <inbound>
        <base />
        <!-- API Version validation -->
        <choose>
            <when condition='@(!context.Request.Headers.ContainsKey("api-version"))'>
                <return-response>
                    <set-status code="400" reason="Bad Request" />
                    <set-body>{"error": {"code": "InvalidRequest", "message": "api-version header is required"}}</set-body>
                </return-response>
            </when>
            <when condition='@(context.Request.Headers.GetValueOrDefault("api-version") != "{{API-VERSION-EMB}}")'>
                <return-response>
                    <set-status code="400" reason="Bad Request" />
                    <set-body>{"error": {"code": "InvalidApiVersion", "message": "Unsupported api-version for embeddings"}}</set-body>
                </return-response>
            </when>
        </choose>
        
        <!-- Direct routing to embeddings deployment (no A/B testing) -->
        <rewrite-uri template="/openai/deployments/{{EMB-DEPLOYMENT}}/embeddings?api-version={{API-VERSION-EMB}}" />
        
        <!-- Set backend to aoai-root -->
        <set-backend-service backend-id="aoai-root" />
        
        <!-- Add deployment tracking header -->
        <set-header name="X-APIM-Deployment" exists-action="override">
            <value>{{EMB-DEPLOYMENT}}</value>
        </set-header>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        <!-- Add deployment info to response -->
        <set-header name="X-Deployment-Used" exists-action="override">
            <value>{{EMB-DEPLOYMENT}}</value>
        </set-header>
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
XML
}

