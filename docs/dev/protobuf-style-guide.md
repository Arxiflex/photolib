# Protobuf style guide

`buf lint` (rules `STANDARD` plus required comments), `buf format` and `buf breaking` enforce what a tool can check;
the gate (`bash tools/check.sh proto`) and CI run them on every change. Review checks the rest.

**Packages and files**

* One package per domain and major version, in `proto/photolib/<domain>/v1/<snake_case>.proto`:
  `photolib.model.v1` (the domain model and the plaintexts of encrypted payloads), `photolib.api.v1` (services and
  their messages), `photolib.sync.v1` (mutations and batches) and `photolib.kernel.v1` (the kernel ABI). The package
  matches the directory, and a message that several domains need lives in `model`.
* Names: messages `PascalCase`, fields `snake_case`, services `<Thing>Service`, RPCs `VerbNoun` with their own
  `<Rpc>Request` and `<Rpc>Response`, enum values `UPPER_SNAKE_CASE` prefixed with the enum's name
  (`AUTH_METHOD_OIDC`).
* Every message, enum, service and RPC carries a comment that says what it is for. A field needs one when its name
  leaves the unit, format or meaning open. `buf format` fixes the layout; run it before committing.

**Identifiers**

* An identifier is a UUIDv7 in its canonical lowercase hyphenated form, as a `string` named `<entity>_id`
  (`asset_id`, `mutation_id`). Bytes are for storage, not for the wire. Time-ordered identifiers let clients mint them
  offline, so the server never has to assign one.

**Time**

* An instant is a `google.protobuf.Timestamp` named `<event>_at` (`recorded_at`). A duration or a size is an integer
  with its unit in the name (`physical_ms`, `size_bytes`); never a float, never a bare number of seconds.
* A moment taken from the real world, such as when a photo was captured, is a `photolib.model.v1.CaptureTime`, never
  a bare instant: the wall clock `local_datetime` plus an explicit zone, as `offset_minutes` and/or an IANA `zone`,
  plus `precision`, `source` and `confidence`. An unknown zone is absent, not zero: readers never assume UTC or the
  viewer's zone, and they do not turn the wall clock into an instant unless the zone is known.

**Enums**

* The first value is `<ENUM>_UNSPECIFIED = 0`, meaning "not set, or not known to this reader". A server rejects it
  where a value is required.
* Readers tolerate unknown values: proto3 enums are open, so a client that sees a number it does not know treats it
  like `UNSPECIFIED` instead of failing. Never reorder, renumber or alias enum values.
* Prefer an enum to a `bool` or a free-form `string` whenever a third state could appear.

**Fields and field numbers**

* Give the numbers 1 to 15, which cost one byte on the wire, to the fields that are present in most messages; use 16
  and up for the rare ones. Numbers 19000 to 19999 are reserved by protobuf itself.
* A field number is forever: never renumber a field, never reuse the number of a removed field, and never change a
  field's type, meaning or `repeated`/`oneof` membership. Add a new field instead.
* The JSON name of a field is its `lowerCamelCase`, and Connect JSON clients depend on it, so a rename is a breaking
  change like any other: add a new field and deprecate the old one.
* Use `optional` when the absence of a value differs from its zero (`offset_minutes = 0` is UTC+00:00, absent is
  unknown). Otherwise use plain proto3 fields. Use `oneof` for alternatives that exclude each other.
* The plaintext of an encrypted payload starts with `uint32 schema_version = 1`, and readers migrate older versions
  (15 §4).

**Removing and changing**

* Deprecate first (`[deprecated = true]` and a comment naming the replacement) and remove only after the
  compatibility window of 16 §5. In the change that removes a field, replace it with
  `reserved <number>;` and `reserved "<name>";`; do the same for removed enum values. `buf breaking` rejects a
  deletion that reserves neither the number nor the name.
* Adding a field, an enum value, an RPC or a message is compatible. Anything else is a breaking change, and an
  unavoidable one becomes a new `v2` package (16 §5).

**Checks and generated code**

* `buf breaking` compares `proto/` with the last release tag (`v*`) and, until the first tag exists, with
  `origin/dev`, so an incompatible change in a pull request fails the gate (`tools/proto_breaking.sh`).
* The generated Rust, Dart and TypeScript is checked in at the consumers' `gen` directories
  (`server/crates/photolib-proto/src/gen`, `app/packages/photolib_api/lib/src/gen`, `viewer/src/gen`) and is never
  edited by hand. After changing a `.proto` file, run `bash tools/codegen.sh install` once and `bash tools/codegen.sh`
  and commit the result. The plugin versions are pinned in `tools/codegen.sh`, and the gate regenerates everything and
  fails on any difference.
