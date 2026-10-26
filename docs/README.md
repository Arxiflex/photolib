# docs/

User, administrator and developer documentation for Photolib, and the architecture decision records (ADRs). This
folder is also the source of the documentation site, and this page is its home.

## Architecture

* The site is built from this folder by MkDocs (`mkdocs.yml`, `bash tools/docs.sh`) and published to GitHub Pages on
  every merge to `main`.
* Each section is a folder whose `README.md` is its index page. A change that alters behaviour updates the matching
  guide in the same pull request; a change that settles an open design question adds an ADR.

## Contents

* [User guide](user/README.md), [Administrator guide](admin/README.md) and [Developer guide](dev/README.md).
* The [architecture decision records](adr/README.md) made here, with their template. The design documents and the
  design's ADRs are in the design repository (below).

## Design

* Design documents
* Quality and testing: Definition of Done
