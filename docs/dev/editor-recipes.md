# Edit recipes and the version history

[ADR-0391](../adr/0391-edit-recipes-and-version-history.md) decides; this page says where the code is and how to run
it.

## The recipe

`proto/photolib/model/v1/edit_recipe.proto` is the plaintext of `versions.recipe`. Operations are in three stages:
the local ones (masked adjustments, inpainting patches) on the original as shown, then the geometry (turn, flip, crop,
as fractions), then the global adjustments, which add up. Stored outputs (masks, patches) keep what a model made, so a
render never runs a model. The kernel (`kernel/src/recipe*.rs`) is the only code that interprets a recipe:

| Method | Does |
|---|---|
| `RESOLVE_RECIPE` (53) | checks the limits, canonical bytes and SHA-256, edited size, the `Develop` of it, provenance |
| `COMPARE_RECIPES` (54) | the steps, outputs and provenance that differ, by id |
| `MAP_REGIONS` (55) | boxes (faces, text) from one version's frame to another's, with the share still visible |
| `RENDER_RECIPE` (56) | the reference render, local operations, geometry, adjustments |
| `RECIPE_FROM_DEVELOP` (57) | the recipe of an alpha copy's `Develop` (ADR-0331) |

`EDIT_COPY` takes a recipe too, and writes IPTC's `DigitalSourceType` and a summary of it into the JPEG's XMP.
`kernel/tests/recipe.rs` and `kernel/tests/edit.rs` prove them; `testvectors/recipe.json` runs in Dart and TypeScript.

## Versions

A device adds a version with a `VersionEdit` mutation and makes it current with a field edit of
`assets.current_version_id`; a revert is that edit alone (`rpc/sync/versions.rs`, `rpc/sync/mutations.rs`, capability
`sync.versions.v1`). Migration 0035 makes versions immutable and gives faces `source_bbox` and `cropped`, and OCR text
its `version_id` and `regions`.

## What follows the current version

* **Faces**: moved in the transaction of the edit from `source_bbox` (the original's frame).
* **Renditions, covers, text, export**: the `follow` job (`edits.rs`) runs the reconciler for the asset; a rendition
  of an image whose `render_spec.version_id` is not the current one counts as missing
  (`photolib-jobs/src/reconcile.rs`), as does text of another `asset_ocr.version_id`, and an edited image without its
  `edit_export` gets an `export` job (`export.rs`). The renderer child applies the recipe
  (`photolib-media/src/render/edit.rs`).
* **Clients**: `GetText` returns the regions; `/media/{asset}/edit_export` serves the export of the current version.

## Running it

```sh
cargo test -p photolib-kernel --test recipe --test edit        # in kernel/
cargo test -p photolib-server --test renditions --test ocr     # in server/, the edit tests
flutter test test/features/editor test/features/viewer/info_versions_test.dart   # in app/
```
