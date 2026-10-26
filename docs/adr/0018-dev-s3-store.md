# ADR-0018 — S3-compatible store for the development stack

* **Status**: Accepted — 2026-10-15 (roadmap M0-04). The owner deferred the choice
  (photolib-design#264),
  so the provisional decision stands.

## Context

The development stack needs an S3-compatible object store so that developers and CI exercise the S3 storage backend
(ADR-0009)
against a real S3 API without a cloud account. The roadmap item names two candidates, Garage and SeaweedFS.

## Decision

Garage, pinned to a release (`dxflrs/garage:v2.4.1`), as one container in a single-node layout with one bucket created
at startup. The compose file is `tools/dev/compose.yaml`.

## Considerations

* Since v2.3, `garage server --single-node --default-bucket` creates the layout, an access key and the bucket from
  environment variables. The stack needs no init container or script, and the key comes from the per-clone
  `tools/dev/.env` that `just bootstrap` generates.
* SeaweedFS is broader (filer, replication, mounts) and has several roles (master, volume server, filer, S3 gateway)
  plus a separate identities file. The development stack needs none of that.
* MinIO is the usual choice for local S3, but its community repository is archived, so it would be pinned to a
  frozen image.
* Garage is AGPL-3.0. It runs as a separate development-only container and is neither linked nor shipped with
  Photolib, so it places no obligation on the code or on the licence decision (ADR-0013).
* Garage implements the core object API (put, get, head, delete, listing, multipart upload, presigned URLs) but not
  every S3 feature: there is no object versioning or object lock, and lifecycle support is partial.

## Consequences

* The S3 backend must stay within the core object API. That is also what NAS and other S3-compatible providers offer,
  so the limit protects users as well.
* Clients use path-style addressing (`http://localhost:3900/photolib-dev/<key>`) and the region `garage`.
* The stack is a developer tool, not a product dependency: nothing is added to a user's installation and nothing
  contacts a third party at run time. Container images are pulled from public registries when a developer
  bootstraps a clone.
* Swapping the store later changes `compose.yaml`, the store's config file and the dev stack test only.
