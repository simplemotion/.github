#!/usr/bin/env bash
#
# provision-claude-app.sh — stand up the Azure side of the SimpleMotion Claude
# GitHub App: Key Vault secret, Entra workload-identity app, RBAC, and the
# GitHub-OIDC federated credential. Idempotent where the Azure CLI allows it.
#
# Prereqs:
#   - az CLI logged in to the SimpleMotion tenant (`az login`) with rights to
#     create app registrations and Key Vaults.
#   - The SimpleMotion-Claude GitHub App already created on github.com, its
#     private key downloaded to a local PEM file (passed via --pem).
#
# What it does NOT do (deliberately manual, per docs/claude-github-app.md):
#   - Install the App into each org (needs org-admin consent).
#   - Set the GitHub org variables/secrets (run scripts described in the docs).
#
# Usage:
#   ./provision-claude-app.sh \
#       --pem ./claude-app.pem \
#       --resource-group sm-automation \
#       --location australiaeast \
#       --vault sm-claude-kv \
#       --app-name SimpleMotion-Claude \
#       [--secret-name claude-app-private-key] \
#       [--workflow-ref "simplemotion/.github/.github/workflows/claude.yml@refs/heads/main"]

set -euo pipefail

PEM=""
RG=""
LOCATION="australiaeast"
VAULT=""
APP_NAME="SimpleMotion-Claude"
SECRET_NAME="claude-app-private-key"
WORKFLOW_REF="simplemotion/.github/.github/workflows/claude.yml@refs/heads/main"
ISSUER="https://token.actions.githubusercontent.com"
AUDIENCE="api://AzureADTokenExchange"

while [ $# -gt 0 ]; do
  case "$1" in
    --pem)            PEM="$2"; shift 2 ;;
    --resource-group) RG="$2"; shift 2 ;;
    --location)       LOCATION="$2"; shift 2 ;;
    --vault)          VAULT="$2"; shift 2 ;;
    --app-name)       APP_NAME="$2"; shift 2 ;;
    --secret-name)    SECRET_NAME="$2"; shift 2 ;;
    --workflow-ref)   WORKFLOW_REF="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

for v in PEM RG VAULT; do
  if [ -z "${!v}" ]; then echo "Missing required --${v,,}" >&2; exit 2; fi
done
[ -f "$PEM" ] || { echo "PEM file not found: $PEM" >&2; exit 2; }

SUB_ID="$(az account show --query id -o tsv)"
echo "Subscription: $SUB_ID"

# 1. Resource group + Key Vault (RBAC authorization mode).
az group create -n "$RG" -l "$LOCATION" -o none
az keyvault create -n "$VAULT" -g "$RG" -l "$LOCATION" \
  --enable-rbac-authorization true -o none
echo "Key Vault: $VAULT"

# 2. Store the App private key as a secret.
az keyvault secret set --vault-name "$VAULT" -n "$SECRET_NAME" --file "$PEM" -o none
echo "Secret stored: $SECRET_NAME"

# 3. Entra app + service principal (federation only — NO client secret).
APP_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)"
if [ -z "$APP_ID" ]; then
  APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
fi
az ad sp show --id "$APP_ID" >/dev/null 2>&1 || az ad sp create --id "$APP_ID" -o none
SP_OID="$(az ad sp show --id "$APP_ID" --query id -o tsv)"
echo "Entra app (client) ID: $APP_ID"

# 4. RBAC: read-only, scoped to the single secret — not the whole vault.
VAULT_ID="$(az keyvault show -n "$VAULT" --query id -o tsv)"
az role assignment create \
  --assignee-object-id "$SP_OID" --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope "${VAULT_ID}/secrets/${SECRET_NAME}" -o none
echo "RBAC: Key Vault Secrets User on ${SECRET_NAME}"

# 5. Federated credential.
#    PRIMARY: flexible match on job_workflow_ref, so trust is pinned to THIS
#    reusable workflow file regardless of which org repo calls it. Validate
#    that flexible federated identity credentials are enabled in the tenant.
FIC_JSON=$(cat <<JSON
{
  "name": "claude-reusable-workflow",
  "issuer": "${ISSUER}",
  "audiences": ["${AUDIENCE}"],
  "claimsMatchingExpression": {
    "value": "claims['job_workflow_ref'] eq '${WORKFLOW_REF}'",
    "languageVersion": 1
  }
}
JSON
)
az ad app federated-credential create --id "$APP_ID" --parameters "$FIC_JSON" -o none \
  && echo "Federated credential (job_workflow_ref) created." \
  || {
    echo "WARNING: flexible FIC create failed — tenant may not support" >&2
    echo "claimsMatchingExpression. Fall back to a dedicated automation repo" >&2
    echo "with an exact subject FIC, e.g.:" >&2
    echo "  \"subject\": \"repo:simplemotion/<automation-repo>:environment:claude-bot\"" >&2
    echo "See docs/claude-github-app.md → 'Federation scoping'." >&2
  }

cat <<SUMMARY

============================================================
Provisioning complete. Set these as org-level Actions variables
(once per org; non-sensitive):

  SM_CLAUDE_APP_ID            = <the GitHub App ID, from github.com app settings>
  SM_CLAUDE_KV_NAME           = ${VAULT}
  SM_CLAUDE_AZURE_CLIENT_ID   = ${APP_ID}
  SM_AZURE_TENANT_ID          = $(az account show --query tenantId -o tsv)
  SM_AZURE_SUBSCRIPTION_ID    = ${SUB_ID}

And one org-level secret:

  ANTHROPIC_API_KEY           = <key>

Then install the SimpleMotion-Claude App into each org (admin consent,
"All repositories"). See docs/claude-github-app.md.
============================================================
SUMMARY
