#!/usr/bin/env bash
#
# provision-claude-app.sh — stand up the Azure side of a SimpleMotion Claude
# GitHub App *family*: Entra workload-identity app + service principal, one
# federated credential PER ORG, Key Vault RBAC, and (optionally) the private
# key secret. Idempotent where the Azure CLI allows it.
#
# ARCHITECTURE (per-tier-1-family, adopted 2026-06-20)
# ----------------------------------------------------
# The enterprise runs ONE Claude App stack per tier-1 org family — a tier-1 org
# plus its numeric-prefix tier-2 children (e.g. the `design` family = 3000 +
# 3400 + 3401-3404 + 3497-3499). Each family has its own GitHub App, Entra app,
# and Key Vault secret, installed ONLY on that family's orgs. Result: a Design
# workflow physically cannot mint a token for a Govern repo, and access follows
# the org tree (grant people the families they should reach). The single shared
# reusable workflow (.github/workflows/claude.yml) is parameterised entirely by
# per-org Actions *variables* — only the inputs differ between families.
#
# WHY ONE FIC PER ORG (not a wildcard, not alternation)
# -----------------------------------------------------
# For the GitHub Actions issuer, Entra flexible FICs accept ONLY the `sub`
# claim (eq / matches), `matches` is GLOB not regex (no alternation), and the
# cap is 20 FICs per app (verified on the SM tenant; reconfirmed on MS Learn
# 2026-06-20). So we create one glob FIC per org:
#     claims['sub'] matches 'repo:<ORG>/*:environment:<ENV>'
# A pattern like `repo:*-SM-*/*` would collapse this to one FIC but is
# SPOOFABLE — org logins are globally registerable, so anyone could claim a
# matching name and assume the identity to read the App key. Enumerate exact
# org logins. Each family is <=9 orgs, comfortably under the 20-FIC cap; that
# is the whole point of sharding by family.
#
# Prereqs:
#   - az CLI logged in to the SimpleMotion tenant with rights to create app
#     registrations and assign Key Vault RBAC.
#   - The family's GitHub App already created on github.com and its private key
#     downloaded to a local PEM (pass --pem to store it; omit to skip).
#
# What it does NOT do (deliberately manual — GitHub's permission model):
#   - Create the GitHub App (no API; use the pre-filled "New App" form).
#   - Install the App into each org (org-admin consent).
#   - Set SM_CLAUDE_APP_ID (needs the App ID, known only after creation) — see
#     the summary the script prints, or the companion finalize step.
#
# Usage:
#   ./provision-claude-app.sh \
#       --entra-app  SimpleMotion-Claude-OIDC-Design \
#       --resource-group sm-automation \
#       --vault sm-claude-kv \
#       --secret-name claude-app-private-key-design \
#       --orgs "3000-0000-SM-Design 3400-0000-SM-Software ..." \
#       [--pem ./sm-claude-design.pem] \
#       [--location australiaeast] [--environment claude-bot]
#
# Tip: families and their org lists are recorded in scripts/claude-families.json.

set -euo pipefail

ENTRA_APP=""
RG=""
LOCATION="australiaeast"
VAULT=""
SECRET_NAME=""
ORGS=""
PEM=""
ENVIRONMENT="claude-bot"
ISSUER="https://token.actions.githubusercontent.com"
AUDIENCE="api://AzureADTokenExchange"

while [ $# -gt 0 ]; do
  case "$1" in
    --entra-app)      ENTRA_APP="$2"; shift 2 ;;
    --resource-group) RG="$2"; shift 2 ;;
    --location)       LOCATION="$2"; shift 2 ;;
    --vault)          VAULT="$2"; shift 2 ;;
    --secret-name)    SECRET_NAME="$2"; shift 2 ;;
    --orgs)           ORGS="$2"; shift 2 ;;
    --pem)            PEM="$2"; shift 2 ;;
    --environment)    ENVIRONMENT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

for v in ENTRA_APP RG VAULT SECRET_NAME ORGS; do
  if [ -z "${!v}" ]; then echo "Missing required --${v,,}" >&2; exit 2; fi
done
[ -n "$PEM" ] && { [ -f "$PEM" ] || { echo "PEM file not found: $PEM" >&2; exit 2; }; }

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
echo "Subscription: $SUB_ID"

# 1. Resource group + Key Vault (RBAC authorization mode). Shared across all
#    families; create-if-absent is idempotent.
az group create -n "$RG" -l "$LOCATION" -o none
az keyvault create -n "$VAULT" -g "$RG" -l "$LOCATION" \
  --enable-rbac-authorization true -o none
echo "Key Vault: $VAULT"

# 2. Entra app + service principal (federation only — NO client secret).
APP_CLIENT_ID="$(az ad app list --display-name "$ENTRA_APP" --query '[0].appId' -o tsv)"
if [ -z "$APP_CLIENT_ID" ]; then
  APP_CLIENT_ID="$(az ad app create --display-name "$ENTRA_APP" \
                     --sign-in-audience AzureADMyOrg --query appId -o tsv)"
fi
az ad sp show --id "$APP_CLIENT_ID" >/dev/null 2>&1 || az ad sp create --id "$APP_CLIENT_ID" -o none
SP_OID="$(az ad sp show --id "$APP_CLIENT_ID" --query id -o tsv)"
OBJ_ID="$(az ad app show --id "$APP_CLIENT_ID" --query id -o tsv)"
echo "Entra app (client) ID: $APP_CLIENT_ID"

# 3. RBAC: read-only, scoped to THIS family's single secret — not the vault.
#    Works even before the secret exists (scope is just a path).
VAULT_ID="$(az keyvault show -n "$VAULT" --query id -o tsv)"
az role assignment create \
  --assignee-object-id "$SP_OID" --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope "${VAULT_ID}/secrets/${SECRET_NAME}" -o none 2>/dev/null || true
echo "RBAC: Key Vault Secrets User on ${SECRET_NAME}"

# 4. Optionally store the App private key as this family's secret.
if [ -n "$PEM" ]; then
  az keyvault secret set --vault-name "$VAULT" -n "$SECRET_NAME" --file "$PEM" -o none
  echo "Secret stored: $SECRET_NAME"
fi

# 5. Federated credentials — ONE glob FIC per org. Created via `az rest` against
#    BETA Graph (`az ad ... federated-credential` is subject-only and rejects
#    claimsMatchingExpression). Idempotent: skips orgs already federated.
FIC_URL="https://graph.microsoft.com/beta/applications/${OBJ_ID}/federatedIdentityCredentials"
EXISTING="$(az rest --method GET --url "$FIC_URL" --query "value[].name" -o tsv 2>/dev/null || true)"
created=0
for org in $ORGS; do
  name="fic-$(echo "$org" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//')"
  name="${name:0:120}"
  if echo "$EXISTING" | grep -qx "$name"; then
    echo "FIC exists: $name"
    continue
  fi
  expr="claims['sub'] matches 'repo:${org}/*:environment:${ENVIRONMENT}'"
  body="$(python3 -c 'import json,sys; print(json.dumps({"name":sys.argv[1],"issuer":sys.argv[2],"audiences":[sys.argv[3]],"claimsMatchingExpression":{"value":sys.argv[4],"languageVersion":1}}))' \
            "$name" "$ISSUER" "$AUDIENCE" "$expr")"
  if az rest --method POST --url "$FIC_URL" \
       --headers "Content-Type=application/json" --body "$body" -o none; then
    echo "FIC created: $name -> repo:${org}/*:environment:${ENVIRONMENT}"
    created=$((created + 1))
  else
    echo "WARNING: FIC ${name} failed for ${org}." >&2
  fi
done
echo "New FICs: ${created} (cap 20 per app; each family is <=9 orgs)."

cat <<SUMMARY

============================================================
Family provisioning complete for: ${ENTRA_APP}

Set these as org-level Actions variables on EVERY org in this family
(non-sensitive):

  SM_CLAUDE_APP_ID            = <the GitHub App ID, from github.com app settings>
  SM_CLAUDE_KV_NAME           = ${VAULT}
  SM_CLAUDE_KV_SECRET         = ${SECRET_NAME}
  SM_CLAUDE_AZURE_CLIENT_ID   = ${APP_CLIENT_ID}
  SM_AZURE_TENANT_ID          = ${TENANT_ID}
  SM_AZURE_SUBSCRIPTION_ID    = ${SUB_ID}

And one org-level secret (shared across all families):

  ANTHROPIC_API_KEY           = <key>

Then install the family's GitHub App into each org (admin consent,
"All repositories"). See docs/claude-github-app.md.
============================================================
SUMMARY
