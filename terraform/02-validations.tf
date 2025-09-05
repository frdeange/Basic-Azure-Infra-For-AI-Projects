#############################################
# 02-validations.tf – Early logical validations (AAD VPN)
#############################################

locals {
  invalid_aad_without_gateway = var.vpn_enable_aad && !var.enable_vpn_gateway
  invalid_aad_and_root_cert   = var.vpn_enable_aad && length(trimspace(var.vpn_root_cert_data)) > 0
  need_external_ids           = var.vpn_enable_aad && !var.create_vpn_aad_apps && length(trimspace(var.vpn_aad_audience)) == 0 && length(trimspace(var.vpn_aad_server_app_id)) == 0
}

resource "null_resource" "aad_vpn_validations" {
  triggers = {
    vpn_enable_aad       = tostring(var.vpn_enable_aad)
    create_vpn_aad_apps  = tostring(var.create_vpn_aad_apps)
    vpn_aad_audience_len = tostring(length(var.vpn_aad_audience))
    root_cert_present    = tostring(length(trimspace(var.vpn_root_cert_data)) > 0)
  }

  lifecycle {
    precondition {
      condition     = !local.invalid_aad_without_gateway
      error_message = "vpn_enable_aad=true requires enable_vpn_gateway=true."
    }
    precondition {
      condition     = !local.invalid_aad_and_root_cert
      error_message = "Do not combine AAD authentication with root certificate in this version (vpn_root_cert_data must be empty)."
    }
    precondition {
      condition     = !local.need_external_ids
      error_message = "Provide vpn_aad_audience or vpn_aad_server_app_id when not creating applications (create_vpn_aad_apps=false)."
    }
  }
}
