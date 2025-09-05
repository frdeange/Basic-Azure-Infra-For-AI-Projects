#############################################
# 16-diagnostics.tf – Diagnostic settings (was gateway-diagnostics.tf)
#############################################

resource "azurerm_monitor_diagnostic_setting" "vpngw" {
  count                      = var.enable_vpn_gateway ? 1 : 0
  name                       = "vpngw-diagnostics"
  target_resource_id         = azurerm_virtual_network_gateway.p2s[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log { category = "GatewayDiagnosticLog" }
  enabled_log { category = "TunnelDiagnosticLog" }
  enabled_log { category = "RouteDiagnosticLog" }
  enabled_log { category = "IKEDiagnosticLog" }
}
