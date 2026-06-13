# SimpleMotion Claude GitHub App (OIDC + Key Vault)

Enterprise setup for running Claude in GitHub Actions across SimpleMotion orgs
under a single, centrally-controlled bot identity — **without storing any
long-lived credential in GitHub**. Mirrors the cert-mint → OIDC migration
(PR #83): no private signing material lives as a GitHub secret.

## Architecture

```
caller repo workflow (workflow-templates/claude.yml)
   │  uses:
   ▼
simplemotion/.github/.github/workflows/claude.yml   (reusable)
   │  1. azure/login@v2 via GitHub OIDC  (id-token: write)
   ▼
Entra ID app  ── federated credential validates the OIDC token,
(workload identity)    trust pinned to THIS reusable workflow
   │  2. returns a short-lived Azure token
   ▼
Azure Key Vault  ── 3. read claude-app-private-key (PEM)
   │
   ▼
actions/create-github-app-token  ── 4. mint 1-hour, repo-scoped token
   │
   ▼
anthropics/claude-code-action    ── 5. run as SimpleMotion-Claude bot
```

The **only** secret stored in GitHub is `ANTHROPIC_API_KEY`. The App private
key exists in Key Vault and transiently (masked) in one runner step.

## Components in this repo

| Path | Role |
|---|---|
| `.github/workflows/claude.yml` | Central **reusable** workflow — does the OIDC → Key Vault → token mint → run. |
| `workflow-templates/claude.yml` | Per-repo **caller stub**, offered org-wide via "New workflow". Carries no secrets. |
| `workflow-templates/claude.properties.json` | Metadata for the template picker. |
| `scripts/provision-claude-app.sh` | Stands up the Azure side (Key Vault, Entra app, RBAC, federated credential). |

## One-time setup

1. **Create the GitHub App** "SimpleMotion-Claude" (owned by the `simplemotion`
   org). Minimal permissions: Contents R/W, Pull requests R/W, Issues R/W,
   Metadata R. Webhook off. Generate a private key → download the `.pem`.
   Register a **second** private key too, so rotation is zero-downtime.

2. **Provision Azure** — from a machine logged in to the tenant:

   ```bash
   ./scripts/provision-claude-app.sh \
     --pem ./claude-app.pem \
     --resource-group sm-automation \
     --location australiaeast \
     --vault sm-claude-kv \
     --app-name SimpleMotion-Claude \
     --orgs "simplemotion 2000-sm-manage 3000-sm-design ..."
   ```

   Delete the local `.pem` afterwards; Key Vault is now the source of truth.

3. **Install the App per org** — admin consent, "All repositories". This step
   is inherently manual (GitHub's permission model); it's the only per-org
   gate, and it's *your* app, so scope/rotation/revocation stay central.

4. **Set org-level Actions variables + secret** (non-sensitive values are
   `vars`, the API key is a `secret`). Scriptable across the org roster:

   ```bash
   gh api user/memberships/orgs --jq '.[].organization.login' | while read -r org; do
     gh variable set SM_CLAUDE_APP_ID          --org "$org" --visibility all --body "$APP_ID"
     gh variable set SM_CLAUDE_KV_NAME         --org "$org" --visibility all --body "sm-claude-kv"
     gh variable set SM_CLAUDE_AZURE_CLIENT_ID --org "$org" --visibility all --body "$AZURE_CLIENT_ID"
     gh variable set SM_AZURE_TENANT_ID        --org "$org" --visibility all --body "$TENANT_ID"
     gh variable set SM_AZURE_SUBSCRIPTION_ID  --org "$org" --visibility all --body "$SUB_ID"
     gh secret   set ANTHROPIC_API_KEY         --org "$org" --visibility all --body "$ANTHROPIC_API_KEY"
   done
   ```

5. **Adopt the caller stub** in repos that want the bot — via the org "New
   workflow" template, or commit `workflow-templates/claude.yml` content to
   `.github/workflows/claude.yml` in the target repo.

## Federation scoping — the critical control

The federated credential decides *which GitHub job* may pull the key. Get this
tight or the whole design is moot.

**Verified tenant behaviour (SM tenant, 2026-06-13).** Flexible FICs *are*
available, but for the GitHub Actions issuer the matching expression accepts
**only the `sub` claim** (with `eq` or `matches`). Every other claim is
refused:

| Expression | Result |
|---|---|
| `claims['sub'] eq '…'` | ✅ accepted |
| `claims['sub'] matches 'repo:simplemotion/.*:environment:claude-bot'` | ✅ accepted |
| `claims['job_workflow_ref'] …` | ❌ "unallowed claim" |
| `claims['repository'] …` / `claims['repository_owner'] …` | ❌ "cannot use operator" |

So you **cannot** pin trust to the reusable workflow via `job_workflow_ref` —
trust can only anchor to the caller repo's `sub`.

- **Primary (used by the provisioning script):** one flexible FIC **per org**,
  wildcarding repos within it and pinning the `claude-bot` environment:

  ```
  claims['sub'] matches 'repo:<ORG>/.*:environment:claude-bot'
  ```

  Trust = (that org) AND (the `claude-bot` environment). The reusable workflow
  sets `environment: claude-bot`, so the caller's OIDC `sub` carries the
  `:environment:claude-bot` suffix and matches. ~33 orgs → ~33 FICs; if you hit
  the per-app FIC limit, use the fallback.

- **Fallback:** run the token-mint only in a single dedicated automation repo
  and federate on an **exact** `sub` (a plain non-flexible FIC works) with a
  protected environment:

  ```
  repo:<automation-repo>:environment:claude-bot
  ```

- **Do NOT** widen the wildcard to `repo:<ORG>/.*` without the
  `:environment:claude-bot` anchor, and never to a cross-org pattern — either
  lets unintended workflows assume the identity and pull the key.

The reusable workflow pins `environment: claude-bot`; attach required reviewers
/ branch filters to that environment for an extra gate.

## Hardening

- **Pin third-party actions to commit SHAs** (`azure/login`,
  `actions/create-github-app-token`, `anthropics/claude-code-action`) before
  enterprise rollout. Tags in the workflow are for readability only.
- **Least privilege everywhere:** the SP can read one secret; the minted token
  is repo-scoped and 1-hour; the App permission set is minimal.
- **Rotate** the App private key periodically; with two registered keys this
  is a single `az keyvault secret set` with no downtime.
- **Never** store the App `.pem` in any repo or as a GitHub secret.

## Notes

- Per this repo's `CLAUDE.md`, changes here apply to `simplemotion` only;
  enterprise-wide rollout of the template is handled via the Orgs rollout
  automation. The reusable workflow is referenced from other orgs' repos by
  its full path `simplemotion/.github/.github/workflows/claude.yml@<ref>`.
