# SimpleMotion Claude GitHub App (OIDC + Key Vault), per‑family

Enterprise setup for running Claude in GitHub Actions across SimpleMotion orgs
under centrally‑controlled bot identities — **without storing any long‑lived
credential in GitHub**. Mirrors the cert‑mint → OIDC migration (PR #83): no
private signing material lives as a GitHub secret.

## Why families (one App stack per tier‑1 org family)

The enterprise has **34 orgs**, but for the GitHub Actions issuer Entra
federated identity credentials (FICs) cap at **20 per app** (see "Federation
scoping" below), and the only non‑spoofable FIC is **one glob per org**. So we
don't run a single global bot. We run **one stack per tier‑1 org family** — a
tier‑1 org plus its numeric‑prefix tier‑2 children:

| Family | GitHub App | Entra app | KV secret | Orgs |
|---|---|---|---|---|
| tier‑0 | `sm-claude-simple`  | `…-OIDC-Simple`  | `claude-app-private-key`         | simplemotion |
| 1000 Client | `sm-claude-client`  | `…-OIDC-Client`  | `…-client` | 1000 |
| 2000 Manage | `sm-claude-manage`  | `…-OIDC-Manage`  | `…-manage` | 2000, 2019–2026 (9) |
| 3000 Design | `sm-claude-design`  | `…-OIDC-Design`  | `…-design` | 3000, 3400, 3401–3404, 3497–3499 (9) |
| 4000 Supply | `sm-claude-supply`  | `…-OIDC-Supply`  | `…-supply` | 4000 |
| 5000 Create | `sm-claude-create`  | `…-OIDC-Create`  | `…-create` | 5000 |
| 6000 Checks | `sm-claude-checks`  | `…-OIDC-Checks`  | `…-checks` | 6000 |
| 7000 Deploy | `sm-claude-deploy`  | `…-OIDC-Deploy`  | `…-deploy` | 7000 |
| 8000 Corpus | `sm-claude-corpus`  | `…-OIDC-Corpus`  | `…-corpus` | 8000 |
| 9000 Govern | `sm-claude-govern`  | `…-OIDC-Govern`  | `…-govern` | 9000, 9001, 9002, 9011, 9012, 9021, 9997, 9998, 9999 (9) |

The canonical map (client IDs, secret names, org lists) lives in
`scripts/claude-families.json`.

Each App is installed **only** on its family's orgs, and each Entra app trusts
**only** its family's orgs. So a Design‑family workflow physically cannot mint a
token for a Govern repo, and access follows the org tree: grant a person the
families they should reach. This is the access boundary — the per‑family split
*is* the control, replacing the earlier exec/employee idea.

Every family is ≤9 orgs, comfortably under the 20‑FIC cap. That headroom is the
reason to shard by family rather than chase one global identity.

## Architecture (identical mechanism for every family)

```
caller repo workflow (workflow-templates/claude.yml)
   │  uses:  (passes this org's family vars: app_id, client_id, kv_secret …)
   ▼
simplemotion/.github/.github/workflows/claude.yml   (ONE shared reusable wf)
   │  1. azure/login@v2 via GitHub OIDC  (id-token: write)
   ▼
Entra ID app for the family  ── federated credential validates the OIDC token;
(workload identity)             trust pinned to repo:<this-org>/*:environment:claude-bot
   │  2. returns a short-lived Azure token
   ▼
Azure Key Vault sm-claude-kv  ── 3. read the family's claude-app-private-key-<family>
   │
   ▼
actions/create-github-app-token  ── 4. mint 1-hour, repo-scoped token
   │
   ▼
anthropics/claude-code-action    ── 5. run as sm-claude-<family>[bot]
```

There is **one** reusable workflow for the whole enterprise; only the per‑org
Actions *variables* differ between families. The only secret stored in GitHub
is `ANTHROPIC_API_KEY` (shared, org‑level). Each App private key exists only in
Key Vault and transiently (masked) in one runner step.

## Components in this repo

| Path | Role |
|---|---|
| `.github/workflows/claude.yml` | Central **reusable** workflow — OIDC → Key Vault → token mint → run. Takes `kv_secret_name` so one vault holds all families' keys. |
| `workflow-templates/claude.yml` | Per‑repo **caller stub**, offered org‑wide via "New workflow". Carries no secrets; reads the family's IDs from org vars. |
| `workflow-templates/claude.properties.json` | Metadata for the template picker. |
| `scripts/provision-claude-app.sh` | Stands up the Azure side **for one family** (Entra app, SP, per‑org FICs, RBAC, optional key). |
| `scripts/claude-families.json` | Canonical family → orgs / IDs / secret map. |

## Per‑family setup

Repeat for each family (the tier‑0 `simple` family already exists — it's the
renamed pilot stack and needs nothing).

1. **Create the GitHub App** for the family (owner: the `simplemotion` org), via
   the pre‑filled "New App" form (there is no API to create a GitHub App).
   Permissions: Contents R/W, Pull requests R/W, Issues R/W, Metadata R.
   Webhook **off**. Set **"Where can this GitHub App be installed?" → Any
   account** (so it can install on the family's other orgs). Generate a private
   key → download the `.pem`. Optionally register a second key for zero‑downtime
   rotation.

2. **Provision Azure** for the family:

   ```bash
   ./scripts/provision-claude-app.sh \
     --entra-app  SimpleMotion-Claude-OIDC-Design \
     --resource-group sm-automation \
     --vault sm-claude-kv \
     --secret-name claude-app-private-key-design \
     --orgs "3000-0000-SM-Design 3400-0000-SM-Software 3401-0000-SM-Simplicity-v01 ..." \
     --pem ./sm-claude-design.pem
   ```

   Delete the local `.pem` afterwards; Key Vault is the source of truth.

3. **Install the App** on each org in the family (admin consent, "All
   repositories"). This is the only per‑org gate, and it's *your* app, so
   scope/rotation/revocation stay central.

4. **Set org‑level Actions variables + secret** on every org in the family. The
   five non‑sensitive values are `vars`; the API key is a `secret`:

   ```bash
   for org in <family orgs>; do
     gh variable set SM_CLAUDE_APP_ID          --org "$org" --visibility all --body "$APP_ID"
     gh variable set SM_CLAUDE_KV_NAME         --org "$org" --visibility all --body "sm-claude-kv"
     gh variable set SM_CLAUDE_KV_SECRET       --org "$org" --visibility all --body "claude-app-private-key-design"
     gh variable set SM_CLAUDE_AZURE_CLIENT_ID --org "$org" --visibility all --body "$AZURE_CLIENT_ID"
     gh variable set SM_AZURE_TENANT_ID        --org "$org" --visibility all --body "$TENANT_ID"
     gh variable set SM_AZURE_SUBSCRIPTION_ID  --org "$org" --visibility all --body "$SUB_ID"
     gh secret   set ANTHROPIC_API_KEY         --org "$org" --visibility all --body "$ANTHROPIC_API_KEY"
   done
   ```

   `SM_CLAUDE_APP_ID` after creation = `gh api /apps/<app-slug> --jq .id`
   (works once the App is public).

5. **Adopt the caller stub** in repos that want the bot — via the org "New
   workflow" template, or commit `workflow-templates/claude.yml` content to
   `.github/workflows/claude.yml`. The target repo must also have a
   **`claude-bot` environment** (matches the FIC subject).

### Caller/runtime requirements (learned from the pilot)

- **Caller must grant token scopes.** A reusable workflow's permissions are
  capped by the caller, and SimpleMotion's org/repo default is read‑only. The
  caller stub declares `permissions: { id-token: write, contents: write,
  pull-requests: write, issues: write }`. Omit it and the run fails at startup
  with a generic "workflow file issue".
- **Checkout before Claude.** The reusable workflow runs `actions/checkout`
  (with the minted token) before `claude-code-action`, which needs a working
  tree to branch from — otherwise: `fatal: not a git repository`.

## Plugin association — the `sm-simple` plugin per family

As of 2026-07-24 the marketplace ships a **single consolidated plugin, `sm-simple`**
(the former per-discipline plugins — `sm-design`, `sm-govern`, … — were merged into it),
so **every family loads `sm-simple`**. When `@claude` runs in a family's repo, the
reusable workflow loads `sm-simple` so the bot carries the full SimpleMotion skill set.

How it loads (set per org via the `SM_CLAUDE_PLUGIN` var — now uniformly `sm-simple`):

1. The plugin source is the **canonical cohort marketplace**
   `simplemotion/sm-executive`. (The single `simplemotion/sm-plugins`
   marketplace was retired/archived; `sm-simple` now lives as a self-contained copy in
   each of the four private cohort marketplaces — `sm-executive` / `sm-employees` /
   `sm-freelance` / `sm-customers` — authored canonically in `sm-executive` and fanned
   out by its `sm-sync-plugin` workflow.) Because that repo is **private**, the family's
   minted token (scoped to the *calling* repo) cannot clone it, so the workflow mints a
   SECOND token from a shared, read-only **marketplace-reader** GitHub App
   (`sm-claude-marketplace-reader`). That App must be **installed on
   `simplemotion` with Contents: read on `sm-executive`** (it previously read
   `simplemotion/sm-plugins`). Its key lives in the same Key Vault
   (`claude-marketplace-reader-key`); every family's service principal has read RBAC on
   that one secret, so the family's existing Azure identity can fetch it — no new
   long-lived credential.
2. The workflow checks out `sm-executive` into `./.sm-plugins` with that read-only token,
   then runs the action with `claude_args: --plugin-dir .sm-plugins/plugins/sm-simple`.
   `--plugin-dir` loads the plugin (and its skills) for that session only.

Both `SM_CLAUDE_PLUGIN` and `SM_CLAUDE_READER_APP_ID` are optional: if either is unset
the bot simply runs with no plugin (still fully functional). Since every family now loads
the same plugin, `SM_CLAUDE_PLUGIN` is `sm-simple` everywhere; the marketplace-reader App
ID is likewise shared across all families — set each once per org (same value everywhere).

## Federation scoping — the critical control

The federated credential decides *which GitHub job* may pull a key. Get this
tight or the whole design is moot.

**Verified tenant behaviour (SM tenant, 2026-06-13; cap reconfirmed on MS Learn
2026-06-20).** For the GitHub Actions issuer the matching expression accepts
**only the `sub` claim** (with `eq` or `matches`). Every other claim is refused:

| Expression | Result |
|---|---|
| `claims['sub'] eq '…'` | ✅ accepted |
| `claims['sub'] matches 'repo:<org>/*:environment:claude-bot'` | ✅ accepted (glob) |
| `claims['job_workflow_ref'] …` | ❌ "unallowed claim" |
| `claims['repository'] …` / `claims['repository_owner'] …` | ❌ "cannot use operator" |

So you **cannot** pin trust to the reusable workflow via `job_workflow_ref` —
trust anchors only to the caller repo's `sub`.

**Capacity limits:**

| Limit | Value |
|---|---|
| Federated credentials per app | **20** |
| `claimsMatchingExpression` value length | **128 characters** |

**`matches` is GLOB, not regex** (verified by real token exchange):
`repo:<org>/*:environment:claude-bot` works; `*` spans within a path segment
and a literal suffix may follow. Regex `.*` and alternation `(a|b)` pass
*creation validation* but **fail at runtime** — do not use them.

**The rule: one glob FIC per org.**

```
claims['sub'] matches 'repo:<ORG>/*:environment:claude-bot'
```

Trust = (this exact org) AND (the `claude-bot` environment). The reusable
workflow sets `environment: claude-bot`, so the caller's OIDC `sub` carries the
`:environment:claude-bot` suffix and matches.

- **Enumerate exact org logins; never pattern‑match across orgs.** A glob like
  `repo:*-SM-*/*` would collapse a family (or the whole enterprise) to one FIC,
  but org logins are globally registerable on github.com — an attacker could
  claim a matching name and assume the identity to read the App key. Sharding by
  family keeps every app under the 20‑FIC cap *without* a loose pattern.
- **Do NOT** drop the `:environment:claude-bot` anchor or widen to a cross‑org
  wildcard — either lets unintended workflows assume the identity and pull a key.

The reusable workflow pins `environment: claude-bot`; attach required reviewers
/ branch filters to that environment for an extra gate.

## Hardening

- **Pin third‑party actions to commit SHAs** (`azure/login`,
  `actions/create-github-app-token`, `anthropics/claude-code-action`) before
  wider rollout. Tags in the workflow are for readability only.
- **Least privilege everywhere:** each SP can read **one** secret (its family's,
  RBAC‑scoped to the secret path, not the vault); the minted token is repo‑scoped
  and 1‑hour; each App's permission set is minimal.
- **Rotate** App private keys periodically; with two registered keys per app
  this is a single `az keyvault secret set` with no downtime.
- **Never** store an App `.pem` in any repo or as a GitHub secret.

## Notes

- Per this repo's `CLAUDE.md`, changes here apply to `simplemotion`; the
  reusable workflow is referenced from other orgs' repos by its full path
  `simplemotion/.github/.github/workflows/claude.yml@<ref>`.
- Adding a new org to a family later = one `provision-claude-app.sh` run (adds
  the org's FIC, idempotent) + install the App on it + set its org vars. A whole
  new tier‑1 family = a new App stack following "Per‑family setup".
