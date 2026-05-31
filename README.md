<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/simplemotion/.github/main/assets/banners/SM-Black.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/simplemotion/.github/main/assets/banners/SM-White.svg">
    <img alt="SimpleMotion" src="https://raw.githubusercontent.com/simplemotion/.github/main/assets/banners/SM-White.svg" width="800">
  </picture>
</p>

<p align="center">
  <em>Engineered for Architecture, Entertainment and Industry.</em>
</p>

# {{ORG_DISPLAY_NAME}} — `.github`

Public org-level defaults for `{{ORG_SLUG}}`.

## What's here

- `profile/README.md` — the org profile, rendered at `https://github.com/{{ORG_SLUG}}`.
- `assets/` — org avatar and public branding assets (see `assets/README.md` for the avatar upload workflow).
- `CONTRIBUTING.md` / `SECURITY.md` / `ISSUE_TEMPLATE/` / `PULL_REQUEST_TEMPLATE.md` — community health defaults that apply to every repo under `{{ORG_SLUG}}` unless overridden per-repo.

## How it's managed

Instantiated from `SimpleMotion-9998-0000-00-Templates/SimpleMotion-9998-0003-00-SM-Template-dot-github`. Cross-org updates happen at the template — changes here apply only to `{{ORG_SLUG}}`. Rollout automation lives in `SimpleMotion-9997-0000-00-Workflows/SimpleMotion-9997-0003-00-Orgs` (`scripts/ensure_orgs_defaults.py`).
