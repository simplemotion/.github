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
# Federation model (VERIFIED against the SM tenant 2026-06-13, see
# docs/claude-github-app.md "Federation scoping"):
#   For the GitHub Actions issuer, Entra flexible FICs accept ONLY the `sub`
#   claim in the matching expression (eq or matches). `job_workflow_ref`,
#   `repository`, and `repository_owner` are all rejected. So we create ONE
#   flexible FIC per org, wildcarding repos within it and pinning the
#   environment:
#       claims['sub'] matches 'repo:<ORG>/.*:environment:<ENV>'
#
# Usage:
#   ./provision-claude-app.sh \
#       --pem ./claude-app.pem \
#       --resource-group sm-automation \
#       --location australiaeast \
#       --vault sm-claude-kv \
#       --app-name SimpleMotion-Claude \
#       --orgs "simplemotion 2000-sm-manage 3000-sm-design ..." \
#       [--environment claude-bot] \
#       [--secret-name claude-app-private-key]

set -euo pipefail

PEM=""
RG=""
LOCATION="australiaeast"
VAULT=""
APP_NAME="SimpleMotion-Claude"
SECRET_NAME="claude-app-private-key"
ORGS=""
ENVIRONMENT="claude-bot"
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
    --orgs)           ORGS="$2"; shift 2 ;;
    --environment)    ENVIRONMENT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

for v in PEM RG VAULT ORGS; do
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

# 5. Federated credentials — flexible FICs, orgs BATCHED via regex alternation.
#    Verified tenant limits (2026-06-13): max 20 FICs per app, and each
#    claimsMatchingExpression value is capped at 128 chars. Only the `sub` claim
#    is accepted for the GitHub issuer. We therefore enumerate exact org logins
#    (not a loose pattern — org names are globally registerable) and greedily
#    pack them into alternation groups that stay under 128 chars:
#        claims['sub'] matches 'repo:(orgA|orgB|orgC)/.*:environment:<env>'
#    34 SM orgs -> ~12 FICs, well under the 20 cap.
#    Created via `az rest` against BETA Graph (`az ad ...` is subject-only).
OBJ_ID="$(az ad app show --id "$APP_ID" --query id -o tsv)"
FIC_URL="https://graph.microsoft.com/beta/applications/${OBJ_ID}/federatedIdentityCredentials"
MAX_LEN=128

mk_expr() {  # $1 = pipe-joined org list
  printf "claims['sub'] matches 'repo:(%s)/.*:environment:%s'" "$1" "$ENVIRONMENT"
}
create_fic() {  # $1 = group index, $2 = pipe-joined org list
  local name="claude-grp-$(printf '%02d' "$1")" expr; expr="$(mk_expr "$2")"
  local body
  body=$(cat <<JSON
{ "name": "${name}", "issuer": "${ISSUER}", "audiences": ["${AUDIENCE}"],
  "claimsMatchingExpression": { "value": "${expr}", "languageVersion": 1 } }
JSON
)
  if az rest --method POST --url "$FIC_URL" \
       --headers "Content-Type=application/json" --body "$body" -o none 2>/dev/null; then
    echo "FIC ${name}: ${2//|/, }"
  else
    echo "WARNING: FIC ${name} failed (group: ${2}). Likely the 20-FIC cap." >&2
    echo "  Fallback: a single dedicated automation repo with an exact-sub FIC:" >&2
    echo "    repo:<owner>/<automation-repo>:environment:${ENVIRONMENT}" >&2
    echo "  See docs/claude-github-app.md -> 'Federation scoping'." >&2
  fi
}

acc=""; n=0
for org in $ORGS; do
  cand="${acc:+$acc|}$org"
  if [ -n "$acc" ] && [ "$(mk_expr "$cand" | wc -c)" -gt "$MAX_LEN" ]; then
    n=$((n+1)); create_fic "$n" "$acc"; acc="$org"      # flush, start new group
  else
    acc="$cand"
  fi
done
[ -n "$acc" ] && { n=$((n+1)); create_fic "$n" "$acc"; }
echo "Created ${n} FIC group(s) (cap 20)."

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
