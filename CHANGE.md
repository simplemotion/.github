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

# Changelog

All notable changes to this project will be documented in this file.

| Version | Hash | Date | Author | Message |
|---------|------|------|--------|---------|
| (auto) | &mdash; | 2026-08-28 03:10 UTC | Greg Gowans | **Host ANNEXE.md, the one canonical copy of the enterprise versioning policy.** The policy is currently reproduced verbatim as an appendix inside every repo's CHANGE.md - 24144 bytes, 74 percent of a fresh changelog, across 426 repos - and keeping those copies in step has already cost 80 reconcile-the-appendix commits. It lands in this repo because this repo is PUBLIC: a pointer from a public repo to an internal file would 404 for outside readers, and keeping inline copies in the three public repos would rebuild the drift this consolidation exists to remove. Publishing it was measured rather than assumed - the text names one org identifier which is already elided in the prose, five sm- names of which sm-release is already public, no people beyond the author who signs every public commit here, and no addresses, money or credentials. The two genuinely new names are sm-mcp-xero and sm-promote. The body is byte-identical to the appendix it replaces and still hashes to the pin sm-pr compares against, so every existing copy keeps validating while the migration runs. |
| v0.0.13-develop-041 | 03243a2 | 2026-08-28 00:33 UTC | Greg Gowans | **Call the shared public-safe gate instead of carrying an inlined copy of it.** The 298-line sm-pr-inline.yml is replaced by the same 24-line stub every public repo now uses. The logic did not change: the shared workflow in this repo was lifted from this very file, so enforcement is identical, plus the SECURE.md heading check the inlined copies never had. This is the repo that hosts the shared workflow, so it calls its own - which is the point, since a public repo can call a public reusable workflow and that is the whole reason the shared gate can exist at all. |
| v0.0.13-develop-040 | b93cc90 | 2026-08-28 00:20 UTC | Greg Gowans | **Add the one public-safe PR gate, so the public repos stop each carrying their own copy.** GitHub refuses a public repo calling an internal reusable workflow - it fails before creating any job, so nothing reports, which is how sm-release sat ungated while taking housekeeping PRs. Public can call public and this repo is public, so the checks now live here once as a workflow_call workflow. Before this there were two inlined copies, sm-install at 360 lines and this repo at 298, and they had already diverged: neither checked SECURE.md and only sm-install carried the renderer and ShellCheck steps. A third copy was about to be written for sm-release. The logic is lifted from this repo's own fork rather than rewritten, so enforcement is unchanged, plus the SECURE.md heading check both copies were missing. It stays a REDUCED gate by design - 3400-9992-SM-PR remains canonical for internal and private repos, and this must not grow toward parity, because a partial copy that looks like the real gate is worse than a small one that admits its scope. Nothing calls it yet: a caller stub referencing main cannot work until the file is on main, so the switchover follows separately. |
| v0.0.13-develop-038 | 4616785 | 2026-08-23 07:38 UTC | Greg Gowans | Inline the CI and PR gates: this repo is public and cannot call an internal workflow (#35) |
| — | — | 2026-08-23 | Greg Gowans | **Inline the CI and PR gates - this repo is PUBLIC and cannot call an internal reusable workflow.** sm-ci.yml was the canonical caller stub and failed at startup on 2026-08-22, the run appearing under the workflow's FILE PATH rather than its name field, which is the tell that GitHub never parsed it. A public repo's call to an internal or private reusable workflow is refused BEFORE any job is created, so the run fails with zero jobs and nothing is validated. A caller stub for sm-pr was opened against this repo the same day by a fleet-wide stub sweep and is closed unmerged: the sweep added the stub to 76 org-default repos without excluding the one public member, which was the sweep's error rather than this repo's. Replaced with sm-ci-inline.yml and sm-pr-inline.yml, following the -inline precedent set by simplemotion/sm-install, the first repo to hit this - its header already states that adding the sm-pr caller stub would reproduce the failure exactly. ADAPTED, not copied: sm-install's PR gate carries a render job that shellchecks sm-install-lib.sh and friends, and this repo has no shell scripts, so that job is deliberately absent rather than copied and left to fail. The hygiene job is the part that applies, and matches what the shared workflow would actually have run here since sm-pr's Rust job is gated on Cargo.toml plus rust-toolchain.toml and this repo has neither. This repo must stay public: it serves the organisation profile and the banner assets every README references by raw githubusercontent URL. It must also never carry has_pr_gate - requiring checks that cannot run would block every PR permanently. |
| — | — | 2026-08-22 | Greg Gowans | **Add the missing SECURE.md.** A required top-level file, absent since this repo was instantiated: the canonical dot-github templates gained SECURE.md after these org-default repos were created, and nothing backfilled them. 32 of the 86 org-default repos across the enterprise were missing it, always both .github and .github-private of the same org, which is the signature of a provisioning-era gap rather than per-repo drift. Latent rather than harmless: sm-pr fails a repo with a required top-level file missing, so every PR here would have been blocked the moment the org gained the PR gate. Body is the canonical template skeleton with its threat model still marked TBD rather than invented. Heading is OWNER-QUALIFIED because every org holds a repo called exactly this, so a bare name identifies 43 different repos - the ambiguity sm-pr names in the check itself. |
| — | 3d5c2c0 | 2026-04-23 06:28 UTC | Greg Gowans | Merge pull request #1 from simplemotion/remove-contributing-security |
| — | a129ecf | 2026-04-23 06:28 UTC | Greg Gowans | Remove SECURITY.md (no longer shipped from org template). |
| — | 452176c | 2026-04-23 06:28 UTC | Greg Gowans | Remove CONTRIBUTING.md (no longer shipped from org template). |
| — | 8006e0f | 2026-04-23 06:13 UTC | Greg Gowans | Initial commit |

---

## Versioning

This repo follows the SimpleMotion enterprise versioning policy. It is kept in
one canonical place rather than copied into every repo, so an amendment lands
once instead of being reconciled across the fleet:

<https://github.com/simplemotion/.github/blob/main/ANNEXE.md>
