# Object storage: Garage, R2, B2 and AWS S3

photolibd keeps managed libraries and database backups on the data directory, the store `local`, or on any
S3-compatible bucket ([ADR-0022](../adr/0022-object-store-backends.md)). A bucket grows without disks to add; it costs
money every month, the provider can read what a standard library holds, and it is not a backup.

## Placement

| On a bucket when placed there | Always on the data directory or `work_dir` |
|---|---|
| `placement.libraries`: each new managed library, every account's *Photos* among them, with its originals, its videos' posters, scrubbing sprites and 720p proxies, and its daily [manifests](backups.md#manifests-and-recovery-from-storage) | Photos' thumbnails and previews (`derived/`), the pre-upgrade dumps, the instance marker, ML models |
| `placement.backups`: the [scheduled database backups](backups.md#scheduled-backups) | Uploads until ingest has read them, jobs' scratch copies of originals, the [streaming](configuration.md#video-streaming) cache |

A library stays on the store it was created on, so set `placement.libraries` before you create accounts: photolibd
cannot move an existing library to another store yet. External libraries are always folders. Size the local disk for
the uploads and jobs that run at once and `streaming.cache_gib`, not for the library.

## Set up a bucket

Create a private bucket for Photolib alone (or a `prefix` per server), with no lifecycle rule that expires objects or
moves them to an archive class (Glacier, R2 Infrequent Access), and a key that may list, read, write and delete in it,
nothing else. photolibd needs neither versioning, object lock, public access nor CORS: every file goes through it.
Then name the store in the [configuration](configuration.md#settings) and restart photolibd; the console's *Storage*
and `photolibd doctor` check the credentials, the marker and the clock, which must be within 15 minutes of the
store's.

```yaml
stores:
  garage:                                 # Garage on your own machines: `garage bucket create photolib`,
    kind: s3                              # `garage key create photolib`, then
    endpoint: http://garage.lan:3900      # `garage bucket allow --read --write --owner photolib --key photolib`
    bucket: photolib
    region: garage                        # Garage's s3_region
    access_key_id: GK31c2…
  r2:                                     # Cloudflare R2: an API token with Object Read & Write on the bucket
    kind: s3
    endpoint: https://<account-id>.r2.cloudflarestorage.com
    bucket: photolib
    region: auto
    access_key_id: 5a1b…
  b2:                                     # Backblaze B2: an application key restricted to the bucket
    kind: s3
    endpoint: https://s3.eu-central-003.backblazeb2.com
    bucket: photolib
    region: eu-central-003
    access_key_id: 0035c…
  aws:                                    # AWS S3: an IAM user with the policy below
    kind: s3
    endpoint: https://s3.eu-central-1.amazonaws.com
    bucket: photolib-example
    region: eu-central-1
    access_key_id: AKIA…
placement:
  libraries: b2
  backups: local
```

Each store's secret goes in the environment, such as `PHOTOLIB_STORES__B2__SECRET_ACCESS_KEY`. With the
[compose bundle](install.md), which has no configuration file, put the store in a `compose.override.yaml` beside
`compose.yaml`, which Docker Compose reads with it and upgrades never replace, and the secret in `.env`:

```yaml
services:
  photolibd:
    environment:
      PHOTOLIB_STORES__B2__KIND: s3
      PHOTOLIB_STORES__B2__ENDPOINT: https://s3.eu-central-003.backblazeb2.com
      PHOTOLIB_STORES__B2__BUCKET: photolib
      PHOTOLIB_STORES__B2__REGION: eu-central-003
      PHOTOLIB_STORES__B2__ACCESS_KEY_ID: 0035c…
      PHOTOLIB_STORES__B2__SECRET_ACCESS_KEY: ${B2_SECRET_ACCESS_KEY:?set it in .env}
      PHOTOLIB_PLACEMENT__LIBRARIES: b2
```

The IAM policy of AWS's key:

```json
{"Version": "2012-10-17", "Statement": [
  {"Effect": "Allow", "Action": ["s3:ListBucket", "s3:ListBucketMultipartUploads"],
   "Resource": "arn:aws:s3:::photolib-example"},
  {"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"],
   "Resource": "arn:aws:s3:::photolib-example/*"}]}
```

B2 keeps every version of a deleted file until a lifecycle rule says otherwise: set the bucket to *Keep only the last
version* unless you want to pay for what Photolib deleted.

## Costs

A provider bills the bytes stored each month, the bytes read out of it (egress) and requests. Photolib stores each
original once, plus about 1 GiB per hour of video for proxies. It reads an object when someone opens an original,
plays or streams a video or downloads, and once for each job that processes it; the
[scrub](console.md#integrity-and-backups) only asks for each object's size and hash, which costs requests, not
egress, unless `rehash_gib_per_month` turns on full reads. List prices in October 2026, before taxes and free tiers:

| Provider | Storage, per TB-month | Egress to photolibd, per GB | Notes |
|---|---|---|---|
| Garage | Your disks, times its replication factor | None | Runs on machines you own: three in different places for redundancy. |
| Cloudflare R2 | $15 | Free | Reads $0.36 and writes $4.50 per million requests. |
| Backblaze B2 | $6.95 | Free up to three times what you store each month, then $0.01 | |
| AWS S3 Standard | $23 | $0.09, free from an EC2 server in the same region | Requests $0.40 (reads) and $5 (writes) per million. |

A family's 1 TB of photos, viewed and backed up from two phones, costs about $7 a month on B2 and $15 on R2; on AWS
from a home server, every 100 GB of originals opened or videos played adds $9.

## Deleting from a bucket

photolibd deletes an original or a rendition from a store only when its owner empties the trash (`EmptyTrash`, a
`trash-empty` job) or an asset has stayed in the trash longer than the console's `trash_retention_days` (30 unless
changed; the daily `trash-expire` job), and then through its
intent log: an asset's rows and the delete intents commit together, so after a crash (`kill -9`) recovery finishes
the deletion and no row is left without its file or file without its row. Nothing relies on bucket versioning or
object lock, and a store that is offline fails the job, which tries again. Over 1,000 assets or 5 % of an account wait
for the owner's confirmation of the count. An external library's files are never deleted
([ADR-0386](../adr/0386-organisation-v1.md)).

## A bucket is not a backup

A bucket is one copy, at one provider, behind one key. A deletion that reaches it (an emptied trash, a purged
account), a leaked key, a closed account, a billing dispute or the provider's own mistake removes it for good, and
photolibd faithfully mirrors a mistake made through it. Keep a second copy with another provider, under other
credentials, with history: [copy the bucket elsewhere](backups.md#backing-up-the-originals) and keep the
[succession kit](backups.md#the-admin-succession-kit) apart from both.

## What the provider can read

photolibd does not encrypt standard libraries on a store. Whoever runs the bucket can read:

* every original as it was uploaded, with its EXIF: places, times, cameras and faces;
* each key, which holds the file name and the month the template puts it in (`libraries/<id>/originals/2024/2024-05/IMG_1234.jpg`);
* the videos' posters, sprites and proxies, and each object's size and BLAKE3 hash;
* the manifests: accounts' sign-in names, titles, descriptions, ratings, tags, favourites and albums;
* the whole database when `placement.backups` points there, accounts, emails and shares included; the
  [OPAQUE key](users.md#the-opaque-key-file) never goes to a store, so its password records test no guess;
* when photolibd reads and writes, and from which address.

[Private libraries](users.md#privacy-on-a-shared-server) hold only ciphertext under opaque names: the provider sees
how many files there are, their sizes and when they come. For what a provider must not see, use a private library or a
store on machines you control.
