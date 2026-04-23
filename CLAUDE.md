# CLAUDE.md

Template for the per-org `.github` repo.

## When working in an instance (org `<slug>/.github`)

- `profile/README.md` renders on `github.com/<slug>` — public. Keep org-appropriate.
- `assets/avatar.png` is the canonical org avatar. Upload via web UI per `assets/README.md`; GitHub has no API for org avatars.
- Community health files (`CODE_OF_CONDUCT.md`, `SECURITY.md`, `CONTRIBUTING.md`, `ISSUE_TEMPLATE/`, `PULL_REQUEST_TEMPLATE.md`) live at the repo root, not under `.github/` (this repo *is* the `.github`).

## When working in the template itself

- Keep content generic / placeholder-driven. Use `{{ORG_SLUG}}`, `{{ORG_DISPLAY_NAME}}`, etc. for org-specific values; provisioning replaces these at instantiation.
- Changes here do NOT propagate to existing instances — those are independent repos after instantiation. Cross-org rollouts happen via `SimpleMotion-9997-0003-00-Orgs/scripts/`.

## IP

All IP assigned to SimpleMotion.Global Pty Ltd per `ASSIGN.md`.
