# proto/

The single protobuf IDL: every wire message, service and kernel call that more than one language touches is
written here once and generated for Rust, Dart and TypeScript.

## Architecture

* Sources live at `proto/photolib/<domain>/v<N>/*.proto`: `api` (services), `model` (domain model and the plaintexts
  of encrypted payloads, each with a `schema_version`), `sync` (sync batches) and `kernel` (the kernel ABI,
  `call(method_id, request) -> response`).
* Transport is Connect over HTTP with binary protobuf for first-party clients and JSON for everyone else.
* `buf lint` and `buf breaking` guard the contract; generated code is reproducible and checked by regenerating and
  diffing in CI. Consumers: `server/crates/photolib-proto`, `app/packages/photolib_api`, `viewer/src/gen`, and
  `kernel/src/gen` (only `photolib.kernel.v1` and what it imports, with ordered maps for byte-identical responses).
* The generated code is committed under each consumer's `src/gen` (`lib/src/gen` for Dart), and nobody edits it by
  hand. After changing a `.proto`, run `bash tools/codegen.sh install` once and `bash tools/codegen.sh`, and commit the
  result; the gate fails when the committed code is stale.
* Conformance fixtures live in `proto/testdata` and `kernel/testvectors/`.

## Contents

* `buf.yaml`: the buf v2 module (lint `STANDARD` plus required comments, breaking `WIRE_JSON`); `buf.gen.yaml`: the
  generation template for Rust, Dart and TypeScript.
* `photolib/<domain>/v1/`: the first messages of the four packages: `model` (`AssetMetaCore`, `CaptureTime`), `api`
  (`ServerInfoService`, `SyncService`, `ErrorDetail`, …), `sync` (`Hlc`, `Mutation`, the `SyncBatch` of typed rows; Dart
  `package:photolib_api/sync.dart`) and `kernel` (`Method`,
  `CallResponse` and the requests and responses of its functions: keys, blobs, local files, capture time, query,
  metadata).
* The generated code. `server/crates/photolib-proto` is the crate of the server's Rust, `app/packages/photolib_api`
  the Dart package and `viewer/` the TypeScript package that wrap it.

## Design

* API, contracts and code generation
* ADR-0005: Protocol Buffers and Connect
