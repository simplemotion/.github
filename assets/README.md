# Org profile assets

Source-of-truth for this org's GitHub profile picture and public branding assets.

GitHub exposes no REST or GraphQL endpoint for setting an org avatar: `PATCH /orgs/{org}` has no avatar field, and there is no `updateOrganizationAvatar` mutation. The internal multipart endpoint used by the web UI requires a browser session cookie, not a PAT — unsupported and fragile. So the image lives here, the upload is manual, and provenance is tracked in git.

## Files

- `avatar.png` — square PNG, ≥500×500, <1 MB. Canonical. The image currently live on `github.com/{{ORG_SLUG}}` should match this file at the SHA recorded in `PROVENANCE.md`.
- `PROVENANCE.md` — append-only log: `YYYY-MM-DD <short-sha> {{ORG_SLUG}} <uploader>`.

## Upload procedure

1. Drop the new image in as `avatar.png`. Commit on its own.
2. `git rev-parse --short HEAD` — grab the SHA.
3. Open `https://github.com/organizations/{{ORG_SLUG}}/settings/profile`.
4. **Profile picture → Upload a photo** → pick `avatar.png` → **Set new profile picture**.
5. Append the line to `PROVENANCE.md`. Commit.
