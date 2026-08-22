<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/simplemotion/.github/main/assets/banners/SM-White.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/simplemotion/.github/main/assets/banners/SM-Black.svg">
    <img alt="SimpleMotion" src="https://raw.githubusercontent.com/simplemotion/.github/main/assets/banners/SM-Black.svg" width="800">
  </picture>
</p>

<p align="center">
  <em>Engineered for Architecture, Entertainment, Industry and Manufacturing.</em>
</p>

# SECURE — simplemotion/.github

> Security posture, threat model, and secrets-handling notes for `simplemotion/.github`.

## Threat model

_TBD — assets, adversaries, trust boundaries._

## Secrets handling

- All credentials follow the SimpleMotion `b64:<base64-payload>` envelope convention.
- No credential material is committed to this repo. Use the home-repo / GitHub Secrets / Keychain path instead.

## Reporting issues

Email **security@simplemotion.com** for any vulnerability discovered in this repo.
