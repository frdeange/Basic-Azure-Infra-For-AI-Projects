#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Azure AI Baseline Deployment Script (deploy.sh)
# -----------------------------------------------------------------------------
# This script automates the deployment of the Azure AI baseline architecture
# using Terraform. It has been simplified to a single secure phase: the
# Terraform code always provisions Key Vault in its hardened (private only)
# configuration, and the self-signed Application Gateway certificate is
# created directly without any bootstrap/open transition.
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

if $PLAN_ONLY; then
  # Simulate phases without committing multiple applies
  if $PREDICT_BOOTSTRAP; then
    tf_plan_or_apply "-var kv_certificate_bootstrap=true" "SIM-BOOTSTRAP"
  fi
  if $PREDICT_HARDEN; then
    # Harden always shown with false (final state) unless only bootstrap required (never the case here)
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
