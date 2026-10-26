# synthlib

Generates realistic synthetic photo libraries at any scale (10k, 100k, 1M assets) as database fixtures and placeholder
media, for performance budgets and client tests (quality and testing §3). A Rust crate with no dependencies.

```sh
cargo run --release --manifest-path tools/synthlib/Cargo.toml -- --assets 1m --seed 42 --out /tmp/lib-1m
```

`--shape` writes one of the pathological libraries of the performance budgets instead
(client app §3.7): `near-duplicates` (every asset in a series of 2 to 13 near-identical shots a second apart,
stacked as `similar_series`), `one-timestamp`, `one-day`, `folders` (5,000 of them) or `albums` (10,000 more, sharing
the assets). The [performance harness](../perf/budgets.json) names the fixtures it measures.

The output directory must be empty or absent. A seed and a generator version give the same bytes (the generator uses
only integer and basic IEEE arithmetic). 1M assets take about 2 s in a release build and fill 348 MB; `cargo test`
generates them too and fails if that takes 10 minutes.

## What it writes

* One CSV table per entity, with a header row and the column names of the domain model: `users`, `people` (humans and
  pets), `assets`, `stacks` (bursts, series), `albums`, `album_items`, `album_members` (sharing) and `faces`. Ids are
  UUIDv7, an empty field is NULL, and capture times follow `CaptureTime` (local time, offset and zone, precision,
  source).
  `folder` is where the file lives (`Pictures/<year>/<year>-<month>`); the frames of a stack share their camera, size
  and placeholder.
* `media/`: one-colour PNG placeholders, 64 px on the long side, shared by every asset of the same shape; the `thumb`
  column of `assets` names the file.
* `manifest.json`: the generator version, the seed, the shape and the rows of every table.

Load the tables into PostgreSQL with `\copy assets FROM 'assets.csv' WITH (FORMAT csv, HEADER true)`, parents first.

## The library

One owner's photos from 1990 to 2025, 12% more each year: film scans dated by hand to the year, month or day, compact
cameras, phones with GPS, then phones that record the time zone (EU summer time at home in Berlin). Days at home,
event days and trips of 2 to 10 days to twelve places (including UTC+05:45 and the southern hemisphere) become albums,
three in ten shared with other users. Videos, panoramas, bursts of 3 to 12 frames, faces of people and pets skewed
towards family, and a few undated assets are mixed in.
