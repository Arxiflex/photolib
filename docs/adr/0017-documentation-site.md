# ADR-0017 — Documentation site: MkDocs published to GitHub Pages

* **Status**: Accepted — 2026-10-15, by the product owner (answers to design#262; roadmap M0-05).
* **Requirements**: R-REL-2 (documentation is versioned with the code).

## Context

The design leaves the site generator and the host open. The site must build in CI from the Markdown in `docs/`,
publish on every merge to `main`, lead readers to the design documents and ADRs, and make readers' browsers fetch
nothing from third parties.

## Decision

* The site is built by MkDocs with its built-in theme (local search, no CDN assets). The version is pinned in
  `tools/docs-requirements.txt`, and the build is strict: a broken link or heading anchor fails the gate.
* `.github/workflows/docs.yml` publishes it to GitHub Pages on every push to `main`; no other host or service.
* The design documents and the design's ADRs stay only in the design repository.
  `docs/adr/` holds the decisions recorded in this repository (ADR-0013 as M0-02 rewrote it, and ADR-0017 on), in the
  same numbering as the design repository; the owner confirmed that this applies only to the copies, not to these ADRs
  (design#286).
* The protobuf style guide, which M0-06 wrote here as §8 of design document 16, is the developer guide's page
  `docs/dev/protobuf-style-guide.md`.

## Consequences

* One command, `bash tools/docs.sh`, builds the site locally, in the gate and in the publish workflow.
* The gate needs Python 3 and, on the first run, network access to PyPI. The pins are not hash-locked.
* Pages needs a one-time setting (Settings → Pages → Source: GitHub Actions). The published site is public if the
  repository is.
* The build needs only this repository and there are no copies to keep in step, but the design documents are read on
  GitHub, outside the site and its search.

## Options considered

* **mdBook**: needs Rust in the documentation build. **Docusaurus or VitePress**: a `package.json`, which the gate
  treats as TypeScript code. **A hand-written renderer**: reinvents Markdown.
* **Read the Docs or another host**: a third-party service, which needs its own ADR.
* **Import the design documents and ADRs into `docs/`** (the provisional choice): one site and one search, but two
  copies that drift apart. **Fetch the design repository during the build, or a Git submodule**: the build depends on
  a second repository.
