# ADR-0331 — Basic edits in the alpha: copies next to the original, lossless where the JPEG allows

* **Status**: **Proposed — owner to confirm** (roadmap M1-22, photolib-design#70).
* **Requirements**: F-10, R-APP-4. **Design**: 11 §1, §2.5, §3, §5, [ADR-0054](0054-editor-rendering.md).

## Context

A gallery that replaces the stock one must edit from the alpha, as OEM editors cannot be opened from it: crop, rotate,
flip and a one-tap auto-enhance, saved as a copy next to the device original until the version model (M8). Design 11
asks that originals are never rewritten, that the copy keeps quality and metadata (capture time, location, ICC), that
JPEG turns and crops are lossless where possible, and that the copy carries its recipe and original so that M8 turns
it into a version. Galleries fail exactly there: Fossify's editor dropped EXIF and overwrote originals, Immich lost
quality and metadata, Ente the resolution.

## Decision

We will save every edit as a new JPEG file next to its original, written by the kernel's `METHOD_EDIT_COPY`:

* **Lossless where the JPEG allows.** Turns and mirrors become the copy's EXIF orientation, composed with the
  original's, its image data and everything after it (a motion photo's video, an Ultra HDR gain map) byte for byte. A
  crop of a sequential JPEG keeps whole blocks of its quantised coefficients, its top left corner moved up and left
  onto the block grid (at most 15 pixels, as jpegtran's `-crop` does), re-coded with Annex K's Huffman tables. Any
  other edit (auto-enhance, a crop of a progressive JPEG) renders the original, decoded by the host, with `develop.rs`
  and encodes it at quality 92 with full-resolution chroma, never coarser than the original's tables.
* **Metadata carried over.** EXIF (its orientation and size rewritten in place, IFD1's stale thumbnail unlinked, the
  Live Photo content identifier in Apple's MakerNote blanked, so that no copy pairs with its original's video), XMP,
  extended XMP, an RGB ICC profile and IPTC; a cropped or encoded copy is a still, so it leaves out what follows the
  image and the XMP saying so (motion photo, container directory, `hdrgm`). A photo sphere turned, mirrored or cropped
  leaves out its GPano projection and shows flat, and faces' mwg-rs regions go with a crop or an encoded turn, which
  move the stored pixels they are in (provisional, owner to confirm).
* **The recipe in the copy.** Its XMP holds `photolib:recipe`, the edit as a canonical `photolib.kernel.v1.Develop`
  (base64; namespace `http://ns.photolib.org/1.0/`), and `xmpMM:DerivedFrom` with `blake3:<hex>` of the original,
  which the app hashes (`photolib_workers`' BLAKE3), so the kernel takes no hash crate; a capture time the original had
  only outside its metadata (a file name, the replica) is written as `exif:DateTimeOriginal`. M8-01's `EditRecipe`
  replaces `Develop`; its migration reads these.
* **Auto-enhance** is computed once on the editor's proxy (grey-world white balance, exposure toward mid grey within the
  highlights, contrast from the tonal spread) and stored as explicit values, which the shaders preview and the kernel
  renders.
* **Verified before it counts** (design 11 §5.1): the kernel reads the copy back as a JPEG with its original's capture
  time, place and RGB colour profile, and the platform's decoder decodes it at 64 px wide, before it is written.
* **Where.** Desktop folders get `<name>_edit.jpg` (`_edit-2.jpg` and on when taken), written to a temporary file and
  renamed; a folder the app cannot write (macOS's read-only bookmarks, ADR-0071) asks with the save dialog, which never
  takes the original; Android gets a new MediaStore item in the original's folder, pending until written. The viewer
  then shows the copy where the original was. iOS (PhotoKit adjustments, M2-21) and browser folders get no editor yet.

## Consequences

* Rotating never costs quality, even of a progressive JPEG; cropping costs none for baseline JPEGs, the usual camera
  output, at the price of up to 15 pixels more at the top or left.
* A turned motion photo or Ultra HDR JPEG stays whole; its video keeps its own orientation (M8 edits composites).
* Formats other than JPEG (HEIC, PNG, WebP) are not editable until M8-07's encoders.
* The kernel holds a JPEG entropy coder and a forward DCT, fuzzed in the gate with every damaged corpus file and
  coverage-guided as `kernel/fuzz`'s `edit_copy` target.

## Options considered

* **Re-encode every edit**: simplest, but every turn and crop loses quality, which design 11 §5.1 rules out.
* **Rotate the coefficients too (jpegtran `-rotate`)**: pixels upright without EXIF, but only when the size is a
  multiple of the block, else it trims or fails; every current viewer honours EXIF orientation.
* **Crop exactly, re-encoding**: no 15-pixel shift, but a lossy copy for the most common edit.
* **An `EditRecipe` message now**: M8-01 designs it with the version model; freezing a subset here would bind it.
