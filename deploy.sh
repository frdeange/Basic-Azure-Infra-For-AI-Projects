#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Azure AI Baseline Deployment Script (deploy.sh)
# -----------------------------------------------------------------------------
# This script automates the deployment of the Azure AI baseline architecture
# using Terraform. Key Vault pasa temporalmente por una fase "bootstrap" solo
# si es necesario para emitir o recrear el certificado, después se endurece.
#
# Features:
#  - Verifies Azure CLI session and confirms user/subscription before proceeding
#  - Offers interactive login (browser or device code) if not authenticated
#  - Single-phase apply (no bootstrap/hardening toggles)
#  - Optional plan-only mode
#  - Optional certificate recreation (taint)
#
# Usage: ./deploy.sh [options]
# -----------------------------------------------------------------------------

set -euo pipefail

# Defaults
VAR_FILE=""
AUTO_APPROVE=false
PLAN_ONLY=false
REINIT=false
NO_COLOR=false
DEBUG=false
RECREATE_CERT=false
ROTATE_SP_SECRET=false
FORCE_BOOTSTRAP=false
ASSUME_YES=false
TF_DIR="terraform"
CERT_NAME="agw-ssl-cert"

log() { echo -e "[INFO] $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
err() { echo -e "\e[31m[ERR ]\e[0m $*" >&2; }

die() { err "$1"; exit "${2:-1}"; }

usage() {
  cat <<EOF
Azure AI Baseline Deployment Script (single-phase)

Options:
  --var-file <f>        Additional tfvars file
  --plan-only           Show plan only (no apply)
  --reinit              Force terraform init -upgrade
  --auto-approve        Pass -auto-approve to terraform apply
  --no-color            Disable terraform colors
  --debug               Enable debug mode (set -x)
  --recreate-cert       Force certificate recreation (terraform taint + bootstrap flow)
  --force-bootstrap     Force bootstrap (treat as if cert missing & vault needs opening)
  --rotate-sp-secret    Rotate (renew) the Service Principal credential AFTER deployment and update Key Vault
  --assume-yes          Skip Azure session confirmation prompt
  --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file) VAR_FILE="$2"; shift 2;;
  --plan-only) PLAN_ONLY=true; shift;;
    --reinit) REINIT=true; shift;;
    --auto-approve) AUTO_APPROVE=true; shift;;
    --no-color) NO_COLOR=true; shift;;
    --debug) DEBUG=true; shift;;
  --recreate-cert) RECREATE_CERT=true; shift;;
  --force-bootstrap) FORCE_BOOTSTRAP=true; shift;;
  --rotate-sp-secret) ROTATE_SP_SECRET=true; shift;;
  --assume-yes) ASSUME_YES=true; shift;;
    --help) usage; exit 0;;
    *) die "Unknown flag: $1" 2;;
  esac
done

$DEBUG && set -x || true

# Prechecks
command -v terraform >/dev/null || die "terraform not found"
command -v az >/dev/null || die "az cli not found"
command -v jq >/dev/null || die "jq not found"
command -v openssl >/dev/null || die "openssl not found"

# Phase prediction flags
PREDICT_BOOTSTRAP=false
PREDICT_HARDEN=false


# Service Principal / App Registration variables
SP_NAME="ai-baseline-deployer"
SP_CLIENT_ID=""
SP_CLIENT_SECRET=""
SP_TENANT_ID=""
SP_SUBSCRIPTION_ID=""
SP_OBJECT_ID=""
APP_APP_ID="" # appId of the AAD Application

# IDs constantes de Microsoft Graph y permiso Application.ReadWrite.All
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"
GRAPH_APP_RWALL_ROLE_ID="5b567255-7703-4780-807c-7be8301ae99b" # Application.ReadWrite.All (application permission)

# Genera certificado y lo asocia (fallback cuando password bloqueada)
setup_certificate_credential() {
  local app_id="$1" exp_date="$2" workdir cert_dir cert_key cert_crt cert_pfx pfx_password
  workdir=$(dirname "$0")
  cert_dir="$workdir/.sp_cred"
  mkdir -p "$cert_dir"
  cert_key="$cert_dir/sp.key"
  cert_crt="$cert_dir/sp.crt"
  cert_pfx="$cert_dir/sp.pfx"
  pfx_password=$(openssl rand -hex 16)
  openssl req -x509 -newkey rsa:2048 -days 1 -nodes -subj "/CN=$SP_NAME" -keyout "$cert_key" -out "$cert_crt" >/dev/null 2>&1 || die "Failed to generate certificate"
  openssl pkcs12 -export -out "$cert_pfx" -inkey "$cert_key" -in "$cert_crt" -passout pass:"$pfx_password" >/dev/null 2>&1 || die "Failed to build PFX"
  az ad app credential reset --id "$app_id" --cert "@$cert_crt" --append --end-date "$exp_date" >/dev/null || die "Failed to add certificate credential"
  export ARM_CLIENT_ID="$app_id"
  export ARM_TENANT_ID="$SP_TENANT_ID"
  export ARM_SUBSCRIPTION_ID="$SP_SUBSCRIPTION_ID"
  export ARM_CLIENT_CERTIFICATE_PATH="$cert_pfx"
  export ARM_CLIENT_CERTIFICATE_PASSWORD="$pfx_password"
  unset ARM_CLIENT_SECRET || true
  export SP_AUTH_MODE="certificate"
  log "Certificate credential configured (expires $exp_date)."
}

# Rotación (usa password si posible, fallback a certificado)
rotate_sp_credential() {
  if [[ -z "$APP_APP_ID" ]]; then warn "Cannot rotate SP credential; APP_APP_ID empty."; return; fi
  local end_date cred_json
  end_date=$(date -u -d "+1 day" +%Y-%m-%dT%H:%MZ)
  log "Rotating credential for SP (appId=$APP_APP_ID)..."
  if cred_json=$(az ad sp credential reset --id "$APP_APP_ID" --end-date "$end_date" -o json 2> >(tee /tmp/cred_rotate_err.log >&2)); then
    SP_CLIENT_ID=$(echo "$cred_json" | jq -r .appId)
    SP_CLIENT_SECRET=$(echo "$cred_json" | jq -r .password)
    export ARM_CLIENT_ID="$SP_CLIENT_ID"
    export ARM_CLIENT_SECRET="$SP_CLIENT_SECRET"
    unset ARM_CLIENT_CERTIFICATE_PATH ARM_CLIENT_CERTIFICATE_PASSWORD || true
    log "Rotated password credential expires $end_date"
  else
    if grep -q "Credential type not allowed" /tmp/cred_rotate_err.log; then
      warn "Password rotation blocked; switching to certificate."
      setup_certificate_credential "$APP_APP_ID" "$end_date"
    else
      warn "Rotation failed; see /tmp/cred_rotate_err.log"
    fi
  fi
}

# Asegura App + SP + credencial (password o certificado)
ensure_sp_application() {
  local app_json existing_app_id end_date cred_json
  SP_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  SP_TENANT_ID=$(az account show --query tenantId -o tsv)

  app_json=$(az ad app list --display-name "$SP_NAME" --query '[0]' -o json)
  if [[ -z "$app_json" || "$app_json" == "null" ]]; then
    log "Creating AAD Application $SP_NAME ..."
    app_json=$(az ad app create --display-name "$SP_NAME" --sign-in-audience AzureADMyOrg -o json)
  else
    log "AAD Application $SP_NAME already exists."
  fi
  existing_app_id=$(echo "$app_json" | jq -r .appId)
  APP_APP_ID="$existing_app_id"

  if ! az ad sp show --id "$existing_app_id" >/dev/null 2>&1; then
    log "Creating Service Principal for appId $existing_app_id ..."
    az ad sp create --id "$existing_app_id" >/dev/null
  else
    log "Service Principal already exists for appId $existing_app_id"
  fi

  if ! az ad app permission list --id "$existing_app_id" -o json | jq -e '.[] | select(.resourceAppId=="'$GRAPH_APP_ID'") | .resourceAccess[] | select(.id=="'$GRAPH_APP_RWALL_ROLE_ID'")' >/dev/null; then
    log "Adding Graph Application.ReadWrite.All permission to app..."
    az ad app permission add --id "$existing_app_id" --api "$GRAPH_APP_ID" --api-permissions ${GRAPH_APP_RWALL_ROLE_ID}=Role >/dev/null || warn "Failed to add Graph permission"
  else
    log "Graph permission Application.ReadWrite.All already present."
  fi
  az ad app permission admin-consent --id "$existing_app_id" >/dev/null 2>&1 || warn "Admin consent for Graph Application.ReadWrite.All not granted (needs tenant admin)."

  end_date=$(date -u -d "+1 day" +%Y-%m-%dT%H:%MZ)
  if cred_json=$(az ad sp credential reset --id "$existing_app_id" --end-date "$end_date" -o json 2> >(tee /tmp/cred_reset_err.log >&2)); then
    SP_CLIENT_ID=$(echo "$cred_json" | jq -r .appId)
    SP_CLIENT_SECRET=$(echo "$cred_json" | jq -r .password)
    export ARM_CLIENT_ID="$SP_CLIENT_ID"
    export ARM_CLIENT_SECRET="$SP_CLIENT_SECRET"
    log "Using password credential (expires $end_date)."
  else
    if grep -q "Credential type not allowed" /tmp/cred_reset_err.log; then
      warn "Password credential blocked by policy; creating certificate credential."
      setup_certificate_credential "$existing_app_id" "$end_date"
    else
      die "Failed to create SP credential; see /tmp/cred_reset_err.log" 1
    fi
  fi
  SP_OBJECT_ID=$(az ad sp show --id "$existing_app_id" --query id -o tsv)
  export ARM_TENANT_ID="$SP_TENANT_ID"
  export ARM_SUBSCRIPTION_ID="$SP_SUBSCRIPTION_ID"
  log "Service Principal ready (appId=$existing_app_id, objectId=$SP_OBJECT_ID)."
}

# Persist secrets en Key Vault solo si existe y aún no guardados
persist_sp_secrets_if_missing() {
  if [[ -z "${KV_NAME:-}" ]]; then return; fi
  if ! az keyvault show --name "$KV_NAME" >/dev/null 2>&1; then return; fi
  local have_id have_secret
  have_id=$(az keyvault secret show --vault-name "$KV_NAME" --name sp-client-id --query value -o tsv 2>/dev/null || true)
  have_secret=$(az keyvault secret show --vault-name "$KV_NAME" --name sp-client-secret --query value -o tsv 2>/dev/null || true)
  if [[ -n "$have_id" && -n "$have_secret" ]]; then
    log "SP secrets already present in Key Vault; skipping persistence."
    return
  fi
  log "Persisting SP secrets into Key Vault $KV_NAME ..."
  az keyvault secret set --vault-name "$KV_NAME" --name sp-client-id --value "$SP_CLIENT_ID" >/dev/null || warn "Failed to store sp-client-id"
  if [[ -n "$SP_CLIENT_SECRET" ]]; then
    az keyvault secret set --vault-name "$KV_NAME" --name sp-client-secret --value "$SP_CLIENT_SECRET" >/dev/null || warn "Failed to store sp-client-secret"
  elif [[ -n "${ARM_CLIENT_CERTIFICATE_PATH:-}" && -f "$ARM_CLIENT_CERTIFICATE_PATH" ]]; then
    local b64_pfx
    b64_pfx=$(base64 -w0 "$ARM_CLIENT_CERTIFICATE_PATH")
    az keyvault secret set --vault-name "$KV_NAME" --name sp-client-cert-pfx --value "$b64_pfx" >/dev/null || warn "Failed to store sp-client-cert-pfx"
    if [[ -n "${ARM_CLIENT_CERTIFICATE_PASSWORD:-}" ]]; then
      az keyvault secret set --vault-name "$KV_NAME" --name sp-client-cert-pfx-password --value "$ARM_CLIENT_CERTIFICATE_PASSWORD" >/dev/null || warn "Failed to store pfx password"
    fi
  fi
  az keyvault secret set --vault-name "$KV_NAME" --name sp-tenant-id --value "$SP_TENANT_ID" >/dev/null || true
  az keyvault secret set --vault-name "$KV_NAME" --name sp-subscription-id --value "$SP_SUBSCRIPTION_ID" >/dev/null || true
  assign_sp_roles || true
}

# Assign RBAC roles (infra scope + Key Vault)
assign_sp_roles() {
  if [[ -z "$SP_CLIENT_ID" ]]; then return; fi
  local rg_id kv_id
  rg_id="/subscriptions/$SP_SUBSCRIPTION_ID/resourceGroups/$(get_output resource_group)"
  if [[ -z "$rg_id" ]]; then
    warn "RG id not yet available for RBAC role assignment"; return
  fi
  kv_id="/subscriptions/$SP_SUBSCRIPTION_ID/resourceGroups/$(get_output resource_group)/providers/Microsoft.KeyVault/vaults/$KV_NAME"
  log "Assigning RBAC roles (Contributor + KV roles) to SP ..."
  az role assignment create --assignee "$SP_CLIENT_ID" --role "Contributor" --scope "$rg_id" >/dev/null 2>&1 || true
  if [[ -n "$KV_NAME" ]]; then
    az role assignment create --assignee "$SP_CLIENT_ID" --role "Key Vault Certificates Officer" --scope "$kv_id" >/dev/null 2>&1 || true
    az role assignment create --assignee "$SP_CLIENT_ID" --role "Key Vault Secrets User" --scope "$kv_id" >/dev/null 2>&1 || true
  fi
}

# Export desde KeyVault (solo si se quiere reutilizar; ahora opcional)
export_sp_secrets_from_kv() {
  if [[ -z "${KV_NAME:-}" ]]; then
    return
  fi
  if ! az keyvault show --name "$KV_NAME" >/dev/null 2>&1; then
    return
  fi
  local cid csec cten csub
  cid=$(az keyvault secret show --vault-name "$KV_NAME" --name sp-client-id --query value -o tsv 2>/dev/null || true)
  csec=$(az keyvault secret show --vault-name "$KV_NAME" --name sp-client-secret --query value -o tsv 2>/dev/null || true)
  cten=$(az keyvault secret show --vault-name "$KV_NAME" --name sp-tenant-id --query value -o tsv 2>/dev/null || true)
  csub=$(az keyvault secret show --vault-name "$KV_NAME" --name sp-subscription-id --query value -o tsv 2>/dev/null || true)
  if [[ -n "$cid" && -n "$csec" ]]; then
    export ARM_CLIENT_ID="$cid"
    export ARM_CLIENT_SECRET="$csec"
    [[ -n "$cten" ]] && export ARM_TENANT_ID="$cten" || true
    [[ -n "$csub" ]] && export ARM_SUBSCRIPTION_ID="$csub" || true
    log "Exported SP credentials from Key Vault."
  fi
}
# --- Azure Login & Subscription Selection ---
confirm_az_session() {
  local account_json sub_id user_name sub_name
  if account_json=$(az account show 2>/dev/null); then
    sub_id=$(echo "$account_json" | jq -r .id)
    user_name=$(echo "$account_json" | jq -r .user.name)
    sub_name=$(echo "$account_json" | jq -r .name)
    echo -e "\nCurrent Azure session detected:"; echo "  User: $user_name"; echo "  Subscription: $sub_name ($sub_id)"; echo "";
    if ! $ASSUME_YES; then
      read -p "Continue with this user and subscription? [Y/n]: " ans
      ans=${ans:-Y}
      if [[ "$ans" =~ ^[Nn] ]]; then
        az_logout_and_login
      fi
    else
      log "Assume-yes enabled; skipping confirmation prompt."
    fi
  else
    az_logout_and_login
  fi
}

az_logout_and_login() {
  echo "No active Azure session detected. Please log in."
  while true; do
    echo "Choose login method:"
    echo "  1) az login (browser)"
    echo "  2) az login --use-device-code (manual)"
    echo "  3) Abort"
    read -p "Select option [1/2/3]: " opt
    case "$opt" in
      1|"")
        az login && break
        ;;
      2)
        az login --use-device-code && break
        ;;
      3)
        die "Aborted by user." 1
        ;;
      *)
        echo "Invalid option. Try again."
        ;;
    esac
    # If login failed, loop again
    if ! az account show >/dev/null 2>&1; then
      echo "Login failed. Try again or choose another method."
    fi
  done
}

confirm_az_session

[[ -d "$TF_DIR" ]] || die "Directory $TF_DIR does not exist"
cd "$TF_DIR"

# Asegurar App/SP y credencial ANTES de terraform init (para que provider use SP)
ensure_sp_application

# Early subscription-scope role assignment so azurerm provider can list resource providers
ensure_subscription_scope_role() {
  local scope role_name existing sp_oid attempt=1 max_attempts=6 sleep_secs=5
  role_name="Reader"
  if [[ "${SP_SUBSCRIPTION_CONTRIBUTOR:-false}" == "true" ]]; then
    role_name="Contributor"
  fi
  scope="/subscriptions/$SP_SUBSCRIPTION_ID"
  # Obtener objectId fiable
  sp_oid=$(az ad sp show --id "$SP_CLIENT_ID" --query id -o tsv 2>/dev/null || true)
  while [[ -z "$sp_oid" && $attempt -le $max_attempts ]]; do
    warn "Service Principal objectId not yet resolvable (attempt $attempt/$max_attempts). Waiting $sleep_secs s..."
    sleep $sleep_secs
    sp_oid=$(az ad sp show --id "$SP_CLIENT_ID" --query id -o tsv 2>/dev/null || true)
    attempt=$((attempt+1))
    sleep_secs=$((sleep_secs*2))
  done
  if [[ -z "$sp_oid" ]]; then
    warn "Could not resolve SP objectId; skipping subscription role assignment."; return
  fi
  existing=$(az role assignment list --assignee-object-id "$sp_oid" --scope "$scope" --query "[?roleDefinitionName=='$role_name'] | length(@)" -o tsv 2>/dev/null || echo 0)
  if [[ "$existing" != "0" ]]; then
    log "Subscription-scope role $role_name already present for SP (objectId=$sp_oid)."; return
  fi
  attempt=1; sleep_secs=5
  while (( attempt <= max_attempts )); do
    log "Assigning subscription-scope role $role_name (attempt $attempt/$max_attempts)..."
    if az role assignment create --assignee-object-id "$sp_oid" --role "$role_name" --scope "$scope" >/dev/null 2>/tmp/role_assign_err.log; then
      log "Subscription role $role_name assigned successfully."; return
    fi
    warn "Role assignment failed (attempt $attempt). Error: $(tr -d '\n' </tmp/role_assign_err.log | head -c 300)"
    sleep $sleep_secs
    attempt=$((attempt+1))
    sleep_secs=$((sleep_secs*2))
  done
  warn "Unable to assign $role_name at subscription scope automatically. Run manually:\naz role assignment create --assignee-object-id $sp_oid --role $role_name --scope $scope"
}

ensure_subscription_scope_role

wait_for_subscription_role() {
  local scope="/subscriptions/$SP_SUBSCRIPTION_ID" i=1 max=6 delay=5
  log "Waiting for RBAC propagation (subscription Reader/Contributor)..."
  while (( i <= max )); do
    if az provider list --query "[0].namespace" -o tsv >/dev/null 2>&1; then
      log "RBAC propagation confirmed after $i attempt(s)."
      return 0
    fi
    warn "RBAC not propagated yet (attempt $i/$max). Sleeping ${delay}s..."
    sleep $delay
    ((i++))
    delay=$((delay*2))
  done
  warn "Continuing despite potential incomplete RBAC propagation. Terraform may need a rerun if it fails with 403."
}

wait_for_subscription_role

if $REINIT || [[ ! -d .terraform ]]; then
  log "Running terraform init..."
  terraform init $($NO_COLOR && echo -no-color || true) $($REINIT && echo -upgrade || true)
fi

TF_APPLY_FLAGS=()
$AUTO_APPROVE && TF_APPLY_FLAGS+=("-auto-approve")
$NO_COLOR && TF_APPLY_FLAGS+=("-no-color")

[[ -n "$VAR_FILE" ]] && [[ -f "$VAR_FILE" ]] && TF_VAR_FILE_FLAG=("-var-file=$VAR_FILE") || TF_VAR_FILE_FLAG=()

# Helpers
get_output() { terraform output -raw "$1" 2>/dev/null || true; }

# -----------------------------
# State Detection Helpers
# -----------------------------

if $PREDICT_BOOTSTRAP; then
  create_or_get_sp
fi
KV_NAME=""
KV_EXISTS=false
KV_PUBLIC_ENABLED=false
CERT_EXISTS=false
PREDICT_BOOTSTRAP=false
PREDICT_HARDEN=false

detect_state() {
  KV_NAME="$(get_output key_vault_name)"
  if [[ -n "$KV_NAME" ]]; then
    if az keyvault show --name "$KV_NAME" >/dev/null 2>&1; then
      KV_EXISTS=true
      local pub
      pub=$(az keyvault show --name "$KV_NAME" -o json | jq -r '.properties.publicNetworkAccess // "Disabled"') || pub="Disabled"
      [[ "$pub" == "Enabled" ]] && KV_PUBLIC_ENABLED=true || KV_PUBLIC_ENABLED=false
      if az keyvault certificate show --vault-name "$KV_NAME" -n "$CERT_NAME" >/dev/null 2>&1; then
        CERT_EXISTS=true
      fi
    fi
  fi
}

export_sp_secrets_from_kv
decide_actions() {
  # Force logic overrides
  if $FORCE_BOOTSTRAP; then
    PREDICT_BOOTSTRAP=true
    PREDICT_HARDEN=true
    return
  fi
  if $RECREATE_CERT; then
    CERT_EXISTS=false
  fi
  # Matrix
  if ! $KV_EXISTS; then
    # Case 1: greenfield -> bootstrap then harden
    PREDICT_BOOTSTRAP=true
    PREDICT_HARDEN=true
  else
    if $CERT_EXISTS; then
      if $KV_PUBLIC_ENABLED; then
        PREDICT_HARDEN=true
      fi
    else
      # Always run a bootstrap pass to (re)create cert with template deployment flag enabled
      PREDICT_BOOTSTRAP=true
      PREDICT_HARDEN=true
    fi
  fi
}

print_predicted() {
  log "Detected state:" 
  echo "  - KV exists:        $KV_EXISTS"
  echo "  - KV public open:    $KV_PUBLIC_ENABLED"
  echo "  - Certificate exists:$CERT_EXISTS"
  log "Planned phases:" 
  echo "  - Bootstrap phase:   $PREDICT_BOOTSTRAP"
  echo "  - Harden phase:      $PREDICT_HARDEN"
}

tf_plan_or_apply() {
  local extra_var="$1" phase_label="$2"
  if $PLAN_ONLY; then
    log "[PLAN][$phase_label]";
    terraform plan "${TF_VAR_FILE_FLAG[@]}" $extra_var
  else
    log "[APPLY][$phase_label]";
    terraform apply "${TF_VAR_FILE_FLAG[@]}" ${TF_APPLY_FLAGS[*]} $extra_var
  fi
}

bootstrap_phase() {
  log "[BOOTSTRAP] Ensuring Key Vault public access enabled for certificate provisioning..."
  # Pre-open existing Key Vault before Terraform refresh to avoid 403 during certificate resource read
  if $KV_EXISTS; then
    log "[BOOTSTRAP] Pre-opening existing Key Vault $KV_NAME via Azure CLI before terraform refresh"
    az keyvault update --name "$KV_NAME" --public-network-access Enabled --set properties.networkAcls.bypass=AzureServices properties.networkAcls.defaultAction=Allow >/dev/null || warn "Could not pre-open Key Vault (may not exist yet)"
  fi
  tf_plan_or_apply "-var kv_certificate_bootstrap=true" "BOOTSTRAP"
  # Re-detect after phase
  detect_state
  if ! $CERT_EXISTS; then
    warn "Certificate not detected immediately after bootstrap apply; retrying lookup..."
    for i in {1..5}; do
      sleep 6
      detect_state
      $CERT_EXISTS && break || true
    done
  fi
  $CERT_EXISTS || die "Certificate still not found after bootstrap phase" 2
  log "[BOOTSTRAP] Certificate present."
}

harden_phase() {
  log "[HARDEN] Applying hardened Key Vault configuration (public disabled)..."
  tf_plan_or_apply "-var kv_certificate_bootstrap=false" "HARDEN"
}

recreate_cert_if_requested() {
  if $RECREATE_CERT; then
    log "Forcing certificate recreation (terraform taint)..."
    terraform taint azurerm_key_vault_certificate.ssl || warn "Could not taint (maybe doesn't exist yet)"
  fi
}

# -----------------------------
# Orchestrated Flow
# -----------------------------

recreate_cert_if_requested
detect_state
decide_actions
print_predicted

# Ensure KV_NAME is initialized before exporting secrets
KV_NAME="$(get_output key_vault_name)"

if $PLAN_ONLY; then
  # Simulate phases without committing multiple applies
  if $PREDICT_BOOTSTRAP; then
    tf_plan_or_apply "-var kv_certificate_bootstrap=true" "SIM-BOOTSTRAP"
  fi
  if $PREDICT_HARDEN; then
    tf_plan_or_apply "-var kv_certificate_bootstrap=false" "SIM-HARDEN"
  fi
else
  if $PREDICT_BOOTSTRAP; then
    bootstrap_phase
  fi
  if $PREDICT_HARDEN; then
    harden_phase
  fi
fi

# Final status & outputs
detect_state

# Persist and/or export SP secrets now that Key Vault (likely) exists
persist_sp_secrets_if_missing || true
export_sp_secrets_from_kv || true
assign_sp_roles || true

# Optional rotation after full deployment
if $ROTATE_SP_SECRET; then
  rotate_sp_credential || warn "Rotation failed"
  persist_sp_secrets_if_missing || true
  # Overwrite secrets deliberately after rotation
  if [[ -n "$KV_NAME" ]]; then
    az keyvault secret set --vault-name "$KV_NAME" --name sp-client-id --value "$SP_CLIENT_ID" >/dev/null || true
    az keyvault secret set --vault-name "$KV_NAME" --name sp-client-secret --value "$SP_CLIENT_SECRET" >/dev/null || true
  fi
fi

log "Relevant outputs:"
for o in resource_group application_gateway_public_ip webapp_default_hostname key_vault_name apim_internal_gateway_url ai_services_name; do
  val=$(get_output "$o" || true)
  [[ -n "$val" ]] && echo "  - $o: $val" || true
done

log "Semantic Caching & OpenAI endpoints:"
for o in semantic_cache_enabled managed_redis_name managed_redis_hostname openai_chat_endpoint openai_responses_endpoint openai_embeddings_endpoint; do
  val=$(get_output "$o" || true)
  [[ -n "$val" ]] && echo "  - $o: $val" || true
done

log "Key Vault final state: public access $( $KV_PUBLIC_ENABLED && echo Enabled || echo Disabled ), certificate $( $CERT_EXISTS && echo Present || echo Missing )."
log "Deployment completed."
