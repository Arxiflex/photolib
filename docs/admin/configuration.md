# Configuring photolibd

`photolibd` reads a YAML file, then `PHOTOLIB_*` environment variables, then `--role`; later sources win. It starts
only when the whole configuration is valid, and says what is wrong when it is not. The choices behind this page are
[ADR-0021](../adr/0021-photolibd-startup-contract.md).

```sh
photolibd --config /etc/photolib/photolib.yaml
photolibd --config photolib.yaml --role api,worker:cpu    # overrides `roles`
```

`PHOTOLIB_CONFIG` names the file when `--config` is absent. The exit code is `0` after a clean shutdown, `2` for an
invalid configuration and `1` for a refused or failed start. `photolibd doctor schema` and `photolibd restore` are
described in [Upgrades and maintenance mode](upgrades.md), `photolibd admin password-setup` in
[accounts](users.md#passwords-and-sign-in).

## Settings

A nested key is set in the environment with a double underscore: `database.url` is `PHOTOLIB_DATABASE__URL`.

| Key | Default | Meaning |
|---|---|---|
| `config_version` | required | Must be `1`. A newer file is refused rather than half understood. |
| `roles` | `all` | A list or a comma separated string of `api`, `scheduler`, `worker:<class>`, `ml`. |
| `listen` | `127.0.0.1:8080` | The one port of `photolibd`: health endpoints, the API, uploads, `/metrics` and `/diagnostics`. |
| `base_path` | `/` | The path every endpoint is served under, such as `/photos` for `https://example.org/photos/` ([reverse proxies](reverse-proxy.md)). |
| `trusted_proxies` | `127.0.0.0/8, ::1` | Addresses or networks whose `X-Forwarded-For` and `X-Forwarded-Proto` count; a list or a comma separated string. |
| `allow_insecure_http` | `false` | Accept sign-ins over plain HTTP from beyond the local networks; logged as a warning at startup. |
| `web_root` | unset | A directory with the web app (`flutter build web --wasm`'s output), which photolibd serves at the root in place of the setup link's page, under a strict Content-Security-Policy with a nonce per page. |
| `discovery` | `true` | Answer the apps' multicast DNS questions (`_photolib._tcp.local`) on the local network with the port, instance, `base_path` and `public_url`, so they list the server under *Add a server*; only when `listen` is not loopback and the process runs `api`. In a container it needs the host's network (`network_mode: host`). |
| `data_dir` | required | The library root; holds `.photolib/instance.json`. Not needed for an `ml`-only process. |
| `opaque_key_file` | `opaque.key` beside the configuration file | The [OPAQUE key](users.md#the-opaque-key-file), never in `data_dir`. Without a configuration file an `api` process needs it set, e.g. `PHOTOLIB_OPAQUE_KEY_FILE=/run/secrets/opaque_key`. |
| `work_dir` | `<data_dir>/tmp` | Scratch space for workers, and uploads in `uploads/` until ingest has read them. |
| `allow_network_fs` | `false` | Accept `work_dir` and `database.data_dir` on NFS, SMB or FUSE. |
| `database.url` | required unless `database.cluster` | A `postgres://` or `postgresql://` URL. It is never logged. |
| `database.cluster` | unset | photolibd runs this PostgreSQL cluster itself, created on first start, from the system's PostgreSQL programs (`database.bin_dir`, `PATH`, or Debian's `/usr/lib/postgresql/<major>/bin`): for a desktop or a package install without Docker or a separate PostgreSQL ([installing](install.md#without-docker)); not with `database.url`. |
| `database.data_dir` | unset | Where a PostgreSQL you run yourself keeps its files, for the filesystem check. |
| `database.pre_upgrade_dump` | `true` | Dump the database to `<data_dir>/backups` before a schema upgrade. |
| `database.keep_dumps` | `3` | How many pre-upgrade dumps to keep; at least 1. |
| `database.bin_dir` | `PATH` | Where `pg_dump`, `pg_restore` and `psql` are. |
| `database.backup_cron` | `0 3 * * *` | When the [scheduled backup](backups.md) runs, five cron fields in UTC; its restore drill follows. |
| `database.keep_backups` | `14` | How many scheduled backups to keep; at least 1. |
| `database.upgrade_from` | unset | The database on the previous PostgreSQL major's cluster, which an empty `database.url` is [copied from](upgrades.md#postgresql-major-upgrades). |
| `log.format` | `json` | `json` (one object per line on stderr) or `text`. |
| `log.filter` | `info` | A level, or per module, for example `info,photolib_server=debug`. |
| `metrics.token` | unset | The bearer token `/metrics` and `/diagnostics` require ([monitoring](monitoring.md), [doctor](console.md#photolibd-doctor)), at least 32 characters; set it as `PHOTOLIB_METRICS__TOKEN`; it is never logged. Unset, there are neither. |
| `traces.otlp_endpoint` | unset | An OTLP/HTTP collector, such as `http://127.0.0.1:4318/v1/traces`, that receives the spans the log shows. Unset, no span leaves the process. |
| `shutdown_grace_secs` | `30` | How long shutdown waits for requests and tasks before cutting them off. |
| `stores.<name>.kind` | required | `s3`, an S3-compatible object store. The data directory is the store `local` and is not configured here. |
| `stores.<name>.endpoint`, `.bucket` | required | The endpoint URL and the bucket. |
| `stores.<name>.region` | `us-east-1` | The region the requests are signed for. |
| `stores.<name>.prefix` | empty | Keys live under it, e.g. `home/`. |
| `stores.<name>.access_key_id`, `.secret_access_key` | required | Set the secret as `PHOTOLIB_STORES__<NAME>__SECRET_ACCESS_KEY`; it is never logged. |
| `stores.<name>.timeout_secs` | `120` | How long one call, such as a 64 MiB part, may take before it fails, with the up to three tries again of a request the store answers with 429 or 5xx. |
| `stores.<name>.rehash_gib_per_month` | unset | Turns on the [scrub](console.md#integrity-and-backups)'s full re-hash of the store, which downloads every original, at most this many GiB a calendar month (UTC). Unset, the scrub only checks each object's size and stored hash. |
| `placement.libraries` | `local` | The store new managed libraries are created on; a library keeps its store until it is moved. |
| `placement.backups` | `local` | The store scheduled backups go to, under `backups/`. |
| `public_url` | unset | The origin people and apps reach photolibd at behind the proxy, such as `https://photos.example.com` (or `http://localhost:<port>` for development), without a path. [Passkeys](users.md#second-factors-and-passkeys) bind to its host; unset, there are none. |
| `exiftool` | empty | ExifTool for the full metadata dump of new assets: its path, or an interpreter and the script, e.g. `[/usr/bin/perl, /opt/exiftool/exiftool]`. Empty, no dump is kept. |
| `ffmpeg_dir` | unset | The directory of the `ffmpeg` and `ffprobe` that render videos, with libx264 or libopenh264. Unset, videos get no posters or proxies. |
| `streaming.sessions` | `2` | How many [streaming](#video-streaming) rungs `api` encodes at once with `ffmpeg_dir`'s FFmpeg; `0` streams only the stored 720p proxies. |
| `streaming.cache_gib` | `20` | The segment cache in `work_dir/streaming/`, with the copies of originals on object stores it encodes from; emptied at start. |
| `oidc.<id>.name`, `.issuer`, `.client_id` | unset | An OpenID Connect provider people [sign in with](users.md#single-sign-on-with-openid-connect): the button's name, the issuer (HTTPS; HTTP only on localhost) and the client registered there. |
| `oidc.<id>.client_secret` | unset | Set it as `PHOTOLIB_OIDC__<ID>__CLIENT_SECRET`; unset for a public client. It is never logged. |
| `oidc.<id>.scopes` | `[openid, profile, email]` | Must include `openid`; add `groups` where the provider asks for it. |
| `oidc.<id>.provision`, `.link_by_email` | `false` | Create an account for a person who has none; link a person to the account with their verified email. |
| `oidc.<id>.roles` | unset | `{claim, admin, user, viewer}`: the role follows the claim at every sign-in; whoever maps to no role is refused. |
| `external_roots` | empty | Absolute paths of the folders under which administrators may add [external libraries](#external-libraries), e.g. `[/srv/photos]`. Empty, there are none. |
| `outbound` | unset | `none` turns off every connection of the [privacy manifest](privacy.md), whatever its own switch says, for air-gapped installs. |
| `webhooks` | `false` | `true` POSTs each account's events to the URLs it registers ([integrations](integrations.md)); `outbound: none` turns them off. |
| `settings.require_two_factor`, `.face_recognition_default`, `.trash_retention_days`, `.min_free_disk_percent`, `.scrub_days`, `.backup_silent_hours` | unset | Pins a [console](console.md) setting: written at every start, read-only in the console and the API, e.g. `settings: {trash_retention_days: 30}`. |
| `settings.policy.<capability>` | unset | Pins a [capability switch](console.md#capability-switches) for the server, over every account's and library's, e.g. `PHOTOLIB_SETTINGS__POLICY__UPLOADS=false`. |
| `ml.runtime` | `libonnxruntime.so` | ONNX Runtime 1.31's library for the [`ml` role](models.md#running-models): its official CPU build, or one with this machine's accelerators. |
| `ml.models_dir` | `<data_dir>/models` | Where models are installed and the `ml` role finds them. |
| `ml.memory_mb` | `2000` | The resident memory, in MB, the process stays under while it runs models; at least 512. |
| `ml.ocr` | `true` | Whether the scheduler and ingest queue an `ocr` job for every image; a process with the `ml` role and a database reads the text of the pictures with the [OCR models](models.md#reading-text-in-photos). `false` reads none. |
| `ml.faces` | `true` | Whether the [`ml` role](models.md#faces) finds faces, for accounts that agreed to it and no others. |
| `ml.face_embedder` | `sface` | The model that describes faces: `sface`, or the optional `auraface` (`photolibd models fetch auraface`). |
| `ml.server`, `ml.token` | unset | On a remote `ml` node, the API it reports to (HTTPS; HTTP only on this machine) and the token it presents, at least 32 characters, set as `PHOTOLIB_ML__TOKEN`. On the API, the token it asks remote nodes for; unset, none can report. |

`worker` classes are `cpu`, `io`, `gpu`, `transcode`, `import` and `export`. `all` runs every role and must be used
alone. Unknown keys and unknown `PHOTOLIB_*` variables are errors, so a typo cannot silently turn a setting off;
those the `photolib` CLI, the compose file and the developer tools read (`PHOTOLIB_TOKEN`, `PHOTOLIB_TOOLS_CACHE`, …)
are not settings and photolibd ignores them.

## Health

| Endpoint | Answers |
|---|---|
| `GET /healthz` | `200` while the process is alive; it checks nothing else. |
| `POST /healthz` | `204` for a body of up to 16 MiB, which it drops: the apps' connection check sends an upload append's 8 MiB to find a proxy that caps requests below it. |
| `GET /readyz` | `200` when every role of this process is ready, else `503`; the body lists each role and its checks. |
| `GET /readyz/{role}` | The same for one role, for example `/readyz/worker:cpu`; `404` for a role this process does not run. |

A role that works on the library is not ready while the database does not answer within two seconds, nor while the
process drains. The `ml` role depends on nothing. Every response carries an `x-request-id` that also appears on the
log lines of that request.

## Sync

Sync delivers a change only once every older transaction has ended, so a transaction left open, for example in a
`psql` session, delays sync for everyone; [monitoring](monitoring.md) alerts on it after 5 minutes. The scheduler also
logs `sync is delayed` once changes have waited that long and `sync caught up` when they no longer wait.
`pg_stat_activity` shows the open transactions, the oldest `xact_start` first.

photolibd keeps a record of each deletion for 90 days: a device offline for longer syncs from scratch.

## Instance marker

The data directory and the database each carry the same instance id, so that a restored, replaced or unmounted side is
noticed instead of being adopted. At startup:

| Data directory | Database | Result |
|---|---|---|
| marker | same marker | start |
| marker | other marker | refused, both ids named |
| marker | none | refused: the database is empty or was replaced |
| none | marker | refused: the volume may be empty or not mounted |
| none, empty | none | both are initialised with a new id |
| none, not empty | none | refused: a non-empty directory is never initialised |

A bare `lost+found` does not make a fresh volume non-empty. A refusal lists who runs the process, who owns the
directory and what it is mounted on, which is usually enough to see a wrong mount or wrong permissions.

## Stores

Each store holds `.photolib/store.json` naming the instance and the store, which the database records
([ADR-0022](../adr/0022-object-store-backends.md)). At startup a fresh, empty store is initialised. A store whose
marker is missing or names another store or instance, a non-empty one without a marker, or one that cannot be reached
is offline: it is logged, nothing in it changes and the rest of the server runs. Every filesystem and object-store call
has a timeout (two minutes on the data directory), so a hung mount or endpoint fails calls instead of stalling the
server. Multi-step file operations are journaled in the database: at startup photolibd rolls back or completes those
that a stopped process left, and aborts uploads older than a day ([ADR-0041](../adr/0041-journaled-file-operations.md)).

A managed library lives in `libraries/<id>/` of its store, with its marker in `.photolib/library.json`. Ingest places
each original once in `originals/` where the library's storage template says, by default
`{{year}}/{{year}}-{{month}}/{{filename}}`; a taken name becomes `IMG_1 (2).jpg`. Changing the template places only
new uploads. Only the `relayout` job, run by `worker:io`, moves originals: to the current template, and with the
library to another store, where each original is copied, checked against its BLAKE3 hash and switched, and its old
copy is deleted a week later. Every 15 minutes the `storage-purge` job deletes what is due
([ADR-0089](../adr/0089-managed-library-layout.md)).

## Uploads

The apps upload with the IETF resumable upload protocol on `/upload` ([ADR-0061](../adr/0061-resumable-uploads.md)),
in pieces small enough for any reverse proxy's request cap, and resume after a lost connection. An upload is
acknowledged only once its BLAKE3 hash matches and it is written to its library's store; its length counts against
the owner's quota from the start. `work_dir` holds the uploads in progress and a copy of each complete one until
ingest has read it, so size it for the largest videos your users upload at once. An upload with no new bytes for a day
expires and its copy is deleted. Uploads pause (`503`, `disk.low`, which `photolib upload` retries) while `work_dir`,
`data_dir` for a library on the local store or `database.data_dir` has less free space than the console's floor: by
default the smaller of 5 % and 20 GB. A file that the uploader's own libraries hold already, external ones included, is
acknowledged without a second copy; the apps ask with `CheckHashes` first and skip it. Duplicates are found within
one account only, so nobody learns what another holds ([ADR-0092](../adr/0092-per-user-deduplication.md)).

A `worker:cpu` role then ingests each complete upload ([ADR-0066](../adr/0066-server-ingest-pipeline.md)): it reads the
metadata and capture time as the apps do, groups the parts of Live Photos and RAW+JPEG pairs sent together, and records
the asset; with `exiftool` set, ExifTool runs sandboxed for the info panel's full dump. Files that are not photos or
videos are kept and listed under other files, dated by their names alone, never parsed, rendered, shared or shown in
the timeline, and download only as files; when an upgrade teaches photolibd a format, a `retype` job checks them again
and turns those it now reads into photos or videos. Uploads into private libraries are never read.

The same role renders every photo's thumbnails (WebP, short side 256 and 720 px) and preview (JPEG, long side 2,160 px)
with libvips in the media sandbox, into `derived/` of `data_dir`, without the photo's metadata
([ADR-0084](../adr/0084-image-renditions.md)). photolibd needs libvips 8.15 or later, and libheif's HEVC plugin for
HEIC (Debian and Ubuntu: `libvips42t64` or `libvips42`, `libheif-plugin-libde265`). The apps fetch files from
`/media/<asset>/<role>` with their session or API key, or with a URL that `POST` there signs for an hour; media on an
object store goes through photolibd too, so the store need not be reachable from clients. Responses say
`Cache-Control: private`: a reverse proxy or CDN must not cache them, and should not log query strings.

With `ffmpeg_dir` set, a `worker:transcode` role renders each video, sandboxed and two at a time, each on half the
cores: its poster frame as the thumbnails and preview, sprite sheets for scrubbing, and a 720p H.264/AAC proxy that
every browser and player plays, tone-mapped to SDR from HDR ([ADR-0085](../adr/0085-video-renditions.md)). A complete
H.264 video of at most 1080p, 60 fps and 5 Mb/s with AAC or MP3 sound in MP4 or MOV plays as it is and gets no proxy.
Renditions are stored next to the original, in its library's store; a proxy takes about 1 GiB per hour of video.

HDR (HDR10, HLG, Dolby Vision profiles 7, 8.1 and 8.4) is converted to SDR with libplacebo where a Vulkan device works
inside the sandbox (the sandbox lets in only the CPU's llvmpipe, from Debian's `mesa-vulkan-drivers`), else with zimg on
the CPU, which matches it within a ΔE of 3.4 ([ADR-0390](../adr/0390-hdr-handling.md)). `tone_mapping: auto` (the
default: libplacebo for posters and sprites, zimg for the proxy and the rungs, which it would take 8 times as long to
convert), `zimg` or `placebo` (everything; a render fails where no device works) chooses; photolibd logs which device
`auto` found. Dolby Vision profile 5
gets no proxy or poster. Pictures of PQ and HLG AVIF and HEIC files are converted the same way, and the preview of a
JPEG, HEIC or AVIF with a gain map (Ultra HDR, ISO 21496-1, Apple's) keeps it. Upgrading to this release renders every
video and image again once.

## Video streaming

Once a video has its proxy, apps and browsers stream it as HLS from `/media/<asset>/hls/master.m3u8`, signed for a
viewer by `POST /media/<asset>/hls` ([ADR-0246](../adr/0246-adaptive-streaming.md)). Players start on a 480p rung at
1 Mb/s and move to the stored 720p proxy and a 1080p rung as the link allows; `?saver=1` offers only the lowest;
`?hdr=1`, which a client that shows HDR adds, offers the original's HDR pictures too,
copied once into the cache and tagged `VIDEO-RANGE=PQ` or `HLG`, for players that have an HDR display. The
`api` role encodes the 480p and 1080p rungs while they are watched, sandboxed, at most `streaming.sessions` at once, a
few seconds ahead of the player, and keeps their segments in `streaming.cache_gib`; when every session is busy, or
`ffmpeg_dir` is unset, the proxy alone streams. A viewer's place in a video (`PUT /media/<asset>/position`) is where
it starts on every device.

## External libraries

An administrator gives an account a read-only library of a folder on the server, under one of `external_roots`, in the
[admin console](console.md) ([ADR-0093](../adr/0093-external-libraries.md)). photolibd never writes there. A folder
that holds or lies in another library, `data_dir`, `work_dir` or `database.data_dir` is refused. A `worker:io` role
scans it a folder at a time, and a restart goes on where the scan stopped; `worker:cpu` reads each new photo's metadata
in place and renders its thumbnails from a copy, so the library is browsable long before it has been read again for
BLAKE3 hashes, which come last. A library is read at up to 1000 files and 64 MiB per second unless set otherwise when
it is added (0 is unlimited); lower that for a spinning disk or a busy NAS. Files that are not photos or videos are
counted, not added, until an upgrade teaches photolibd their format, when the `retype` job reads them again; a file that
cannot be read is recorded with the reason, and a folder that cannot be read keeps what it held.

Each `worker:io` role watches the library's folders with inotify, up to half of `fs.inotify.max_user_watches`, and a
new file shows within seconds; folders past that limit (the log says so; raise it with `sysctl`) and libraries on NFS,
SMB or FUSE are scanned again every hour, every other library every day. A sync tool can announce new files with
`HintPaths` ([ADR-0257](../adr/0257-external-change-detection.md)). Moved and renamed files keep their assets. Files
a scan no longer finds, or that a `.photolibignore` (gitignore syntax) now excludes, are marked missing, never
deleted, and come back when found; a scan that would mark more than 1,000 assets or 5 % of the library waits for
`ConfirmScan`. A root that lacks every name it held, is empty or cannot be read, as an unmounted share, puts the
library offline and changes nothing in it. When the share moves, `RelocateLibrary` points the library at its new path.

## Network filesystems

File locking and `fsync` cannot be trusted on NFS, SMB/CIFS or FUSE (`fuse*`, including `fuseblk`), so
`work_dir` and `database.data_dir` on one stop startup. The library itself may live on a share. If you accept the risk,
set `allow_network_fs: true`. The check reads `/proc/self/mountinfo`; if that is unreadable the check is skipped and a
warning is logged.

## Media sandbox

Media files are parsed only in `photolibd media-child` processes, which the workers start without network access,
with read access to one library and with memory, CPU and time limits ([ADR-0024](../adr/0024-media-sandbox.md)). File
access is confined with Landlock, which needs Linux 5.13; signal isolation needs Linux 6.12. On an older kernel the
children still run and the log says `sandbox: partial`.

## Shutdown

`SIGTERM` (or `SIGINT`) makes readiness fail at once, so a load balancer stops sending traffic. In-flight requests and
tasks then get `shutdown_grace_secs` to finish. What is left is cut off, and the jobs still leased to the process go
back on the queue for another one.

## Background jobs

Background work runs as jobs stored in PostgreSQL, with no other service. A job whose process died is retried by
another after its one-minute lease; one that fails five times waits in the dead-letter queue. Scheduled jobs use UTC.
An idle server writes nothing to disk, so NAS disks can spin down ([ADR-0034](../adr/0034-job-queue.md)).
