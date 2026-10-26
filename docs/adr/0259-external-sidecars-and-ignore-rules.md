# ADR-0259 — Ignore rules and sidecars of external libraries

* **Status**: Accepted — 2026-10-23 (roadmap M2-29). The owner kept all three decisions as made, which
  photolib-design#715 cites as ADR-0229, this ADR's number before renumbering: a scan lists a Takeout's JSON as
  unsupported until its importer, flat keywords are dropped against every node of the asset's keyword trees, and
  every asset ingest makes, uploads too, gets its keywords as tags
  (photolib-design#715).
* **Requirements**: R-MODE-3, F-07, LIB-11. **Design**:
  storage and libraries §4,
  import, export and migration §7.

## Context

ADR-0093's scans recorded every regular file under a root, a NAS's thumbnail folders and recycle bins too. The design
names the default ignore list and `.photolibignore` files in gitignore syntax, which the apps' folder sources and
`photolib upload` already run (ADR-0042, `testdata/photolibignore.json`). It leaves open how a scan that is a job per
folder learns the rules of the folders above it, and how the server, which may run anywhere, tells a volume's case.

The same scans read no sidecar: a Lightroom or digiKam archive's ratings and keyword trees, kept in `IMG.xmp` or
`IMG.jpg.xmp` beside the photos, were lost, and the files were listed as unsupported. Design 13 §7.2–§7.4 says how a
sidecar ranks against the photo's own metadata and how keywords become tags, but not which sidecars a folder scan
reads before the importers (M4) exist, or how the server keeps them.

## Decision

1. **One implementation of the rules in Rust.** `photolib-ignore` holds the port of the apps' `ignore.dart` that
   `photolib upload` used; the CLI and the scans share it and its cases.
2. **Rules travel down the scan.** A folder's `scan` job reads its `.photolibignore` (at most 64 KiB, at the library's
   file rate, within the root's timeout) and passes the texts of every one above it, with the volume's case
   sensitivity, in the payload of each subfolder's job. What the rules name is never recorded, listed or read; a
   `.photolibignore` is read, never recorded as a file of the library.
3. **Case as the volume tells it.** The scan's first job probes the root as the apps do, without writing: the first
   name with a case, looked up in the other case through the root's descriptor, is the same file or folder only on a
   volume that ignores case. A root with no such name is case-sensitive, as Linux's file systems are.
4. **Sidecars by name.** In an ingest batch, which never splits a name's stem, `<name>.xmp` and `<stem>.xmp` (`xmp` in
   any case) of a photo or video are its XMP sidecars: the kernel's `ReadMetadata` reads each whole, up to 4 MiB, the
   only files that are no photo or video a parser reads. The sidecars of every file of a group (a RAW+JPEG pair, a
   Live Photo) are the asset's; one named after photos that stay apart (`IMG.jpg`, `IMG.png`) is the first's by name.
5. **Sidecars over the file, keywords merged** (design 13 §7.2): their title, description, rating, label and location
   (`location_source = 'sidecar'`) replace the file's, and their keywords join its own. Of several, the newer
   `xmp:MetadataDate` wins, and on a tie `<name>.xmp` over `<stem>.xmp`.
6. **Keywords become tags** (design 13 §7.4) for every asset ingest makes, uploads too: a hierarchical keyword
   (`lr:hierarchicalSubject`, `digiKam:TagsList`) a tree of the owner's tags whose leaf tags the asset, a flat one
   (`dc:subject`, IIM) a tag at the root unless it names a node of the asset's trees, all with origin `import`.
7. **Kept, not interpreted.** A sidecar is a `sidecar` file of its asset, in place, hashed with the photo and served
   only as a download (`application/octet-stream`): an XML document a browser shows could run script. What the kernel
   does not read (`crs:`, `darktable:`) stays in the file for the merge-preserving writer (M3-08).
8. **Takeout's JSON waits for its importer.** Design 13 §2.1 has a scan that recognises a Takeout offer the importer,
   whose matching (counters, truncated names) and validation dates and places need (§6.2, M4-02); until then a scan
   lists a Takeout's JSON as unsupported, as it does Apple's AAE.

## Consequences

* ✅ NAS thumbnails (`@eaDir`), recycle bins and desktop litter never become files of a library, and a user excludes
  folders as on the desktop (`external::tests::a_scan_skips_what_the_ignore_rules_name`).
* ✅ What an earlier scan recorded before a rule named it turns missing at the next scan (M2-28, ADR-0257).
* ⚠️ The probe of a case-insensitive volume runs only on such a volume (SMB, exFAT), which the gate has none of.
* ✅ The hierarchical keywords and ratings of digiKam's and Lightroom's sidecars become tags and ratings
  (`external::tests::sidecar_keywords_and_ratings_become_tags_and_ratings`), and the sidecars files of their asset.
* ⚠️ A sidecar added or changed after its photo was scanned is read again only by change detection (M2-28); a new one
  meanwhile is listed as unsupported.
* ⚠️ A sidecar's dates are no claims yet: the resolver takes the host's QuickTime and Takeout claims only. Two
  sidecars that disagree are not recorded as a conflict, and person keywords (Lightroom's `keywordType=person`) are
  tags, not people hints (M5-12).
* ⚠️ darktable's duplicates (`IMG_1234_01.CR2.xmp`) match no photo and stay unsupported until versions (M3-08).

## Options considered

* **Flat keywords de-duplicated against leaves only**, as design 13 §7.4 says: Lightroom writes a keyword's parents
  into `dc:subject` too, so `Places` and `France` would become tags beside `Places|France|Paris`.
* **Takeout JSON by exact name now**: a counter's or a truncated name's JSON pairs wrongly (design 13 §6.2), and dates
  and places would come from a sidecar no validation chose.

* **Each job reading every `.photolibignore` above it**: as many reads per folder as it is deep, on the disks the rate
  limits spare.
* **The server's own case (Linux: sensitive)**: a share from a Windows or Synology box ignores case, and the apps' rules
  for the same folder would skip other files than the server's.
