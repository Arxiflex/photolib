# ADR-0391 — Edit recipes and the version history: an `EditRecipe` per immutable version, derived data that follows

* **Status**: **Proposed — owner to confirm** (roadmap M8-01).
* **Requirements**: F-05, F-10, R-REL-2. **Design**: 11 §2, 04 §4.3,
  [ADR-0054](0054-editor-rendering.md), [ADR-0265](0265-mutations-outbox-merge.md),
  [ADR-0331](0331-basic-edits-saved-as-copies.md), [ADR-0388](0388-ocr-and-text-search.md).

## Context

The baseline schema has `versions` (an immutable history), `assets.current_version_id` and `faces.version_basis`, and
the replica has `asset_version`; nothing wrote or read them but ingest's first version. The editor of the alpha writes
copies (ADR-0331) whose XMP holds a `Develop`, and says that M8-01's `EditRecipe` replaces it. Design 11 and 04 are not
in this repository (ADR-0017); this takes the most conservative reading of the item and lists what it chose below.

## Decision

* **The recipe** is `photolib.model.v1.EditRecipe` (`proto/photolib/model/v1/edit_recipe.proto`): a schema version,
  ordered `Operation`s with ids (turn, flip, crop, adjust, LUT, masked adjust, inpaint), the `StoredOutput`s of models
  those operations use (an 8-bit mask, an RGBA patch, with the model, its version and its parameters) and the
  `Provenance` (tool, models, IPTC `DigitalSourceType`). A render applies the **local** operations to the original as
  shown, in list order, then the **geometry**, then the **global** adjustments, summed: stored outputs are in the
  original's frame, so a crop changed later keeps them valid, and **no model ever runs again** to render.
* **The kernel owns the rules** (`kernel/src/recipe*`, methods 53 to 57): `ResolveRecipe` checks limits (256
  operations, 64 outputs of at most 8192² and 64 MiB together, ids, ranges), puts the recipe in a canonical form with
  its SHA-256 and derives the provenance (human edits, algorithmically enhanced by a model's mask, composite with
  trained algorithmic media for a model's patch; a caller's claim is replaced); `CompareRecipes` lists added, removed,
  changed and moved steps and outputs by id; `MapRegions` moves boxes through the crop, turns and mirrors of any two
  versions; `RenderRecipe` is the CPU reference; `RecipeFromDevelop` reads the alpha's copies. `EditCopy` takes a recipe
  too (lossless for a geometry-only edit of a JPEG; the XMP gets the recipe without its pixels, its SHA-256, models and
  parameters, and IPTC's `DigitalSourceType`) and, for a picture the host rendered, keeps the metadata of the file it
  came from (`rendered`, `metadata_from`).
* **Versions travel as mutations** (ADR-0265): `VersionEdit` adds an immutable version (checked by the kernel, at most
  500 per image asset, a private library's refused: its recipes stay on devices); `assets.current_version_id` is an
  ordinary field with the per-field clock, so **a revert is one edit** and no version changes (a trigger refuses it).
  Capability `sync.versions.v1`. The replica needs no new table: `asset_version` and `asset.current_version_id` exist.
* **Derived data follows the current version.** A change of version, in the transaction of the edit, moves the asset's
  faces to its frame from their box in the original's frame (`faces.source_bbox`; a face less than half in the frame
  is `cropped`, keeps its last box, and returns with a revert) and queues a `follow` job, which lets the reconciler
  queue the rest: renditions whose `render_spec.version_id` is not the current one, OCR whose `asset_ocr.version_id` is
  not (text read before versions stands while the current version is no edit), and one `export` job. The renderer
  child applies the recipe with the kernel to the upright decoded picture before it fits the outputs (edited pictures
  are sRGB, at most 48 MP decoded; a JPEG is decoded at the size the outputs need), so thumbnails, previews, covers
  (which name an asset), the text OCR reads and its `regions` are the edited picture's. `GetText` returns the regions
  of the current version only.
* **The export** is role `edit_export`, one JPEG per edited image and current version, served by `/media/{asset}/
  edit_export` only while its version is current. Lossless where the kernel can, else rendered in the sandbox and
  given the original's EXIF, XMP and IPTC; a picture of another format gets its capture time and the provenance only.
* **Clients.** `Mutations.addVersion` and `revert`; `Edit.recipe`, `appendedTo` (a new edit continues the steps of the
  version it was made on) and `fromRecipe`; the editor saves a **version** for photos only the server has and a copy
  for files on the device; the info panel's edit history lists versions with what each changed and reverts; downloads
  offer the edited version.

## Consequences

* A device file that is backed up keeps showing the file, and is edited into a copy (ADR-0331), whatever versions the
  server holds of its asset: showing the server's edited rendition for it waits for the unified item of M2-24.
* The edit history of a linked device item lists the asset's versions; the Compare with original chip needs a picture
  of the original, so it shows for device items only.
* Old `edit_export` files stay until the next export of the asset or its deletion.
* The kernel's size grows by about 60 KB; the budget of ADR-0004 holds.

## Evidence

* A real photolibd, driven by the signed-in app's replica (`app/test/live/versions_test.dart`): a crop added as a
  version makes the thumbnail and the export the cropped picture, and a revert brings the original back.
* The kernel's recipe vectors run natively, in the Dart binding, in TypeScript's tests and in Chrome and Firefox on
  dart2js and dart2wasm (`dart test -p chrome -p firefox -c dart2js -c dart2wasm test/web_vectors_test.dart`).
* The viewer's menu and edit history at a phone's 390 px width ([menu][menu], [history][history],
  [older][older]) are widget renders of the viewer test harness with Roboto and the Material icons loaded, at pixel
  ratio 1.5. The web app has no server items (no sync there), so a browser cannot show them.

## Options considered

* **A new `EditService`** for create, list and compare: more surface, authz rows and a second write path; the mutation
  path is offline-first and already merges.
* **Recipes in clear and masks as files**: the XMP would exceed 64 KB; masks live in the recipe, summarised in the XMP.
* **Rewriting faces' boxes without `source_bbox`**: a crop would lose faces for good, a revert could not bring them back.
* **Rendering the export in the app**: the server has the original and the sandbox; the app downloads the result.

## For the owner to confirm

Design 11 and 04 were not available. C2PA (optional in EDP-30) is not built. Private libraries' versions stay on
devices. Person covers are not rewritten when a crop hides the cover face (the face is `cropped`). Server edit renders
stop at 48 MP of decoded source.

[menu]: assets/0391/viewer-menu-widget-render.jpg
[history]: assets/0391/edit-history-widget-render.jpg
[older]: assets/0391/edit-history-older-widget-render.jpg
