# Runbooks

What to do when something has to change or went wrong, for the [compose bundle](install.md): run the commands in its
directory (`cd photolib`). `docker compose run --rm photolibd <command>` runs a `photolibd` command with the bundle's
settings; on other installs run the same command with their configuration. Know these before you need them, and keep
the [admin-succession kit](backups.md#the-admin-succession-kit) current, as some of them start from it.

## Upgrade

1. In the console's *Overview*, check that today's backup has a verified restore, and read the release notes' *Breaking
   / action required*.
2. Fetch the bundle's new files and start the new release, as [installing](install.md#upgrade) shows. photolibd dumps
   the database and migrates it ([upgrades](upgrades.md)).
3. `curl -s https://photos.example.com/readyz` answers `200` once it is done; a `503` that says `maintenance` is a
   failed upgrade.

## A failed upgrade

The upgrade was rolled back: the schema is as it was, and `/readyz` and `docker compose logs photolibd` say what failed.
Fix the cause (a full disk, a missing permission of the database role) and `docker compose restart photolibd`. Or go
back to the release you ran, which also undoes a release that started but misbehaves, losing what changed since:

```sh
docker compose stop photolibd
docker compose run --rm photolibd restore    # the newest pre-upgrade dump
# set PHOTOLIB_VERSION in .env to the release you ran before
docker compose up -d
```

## Restore a database dump

To undo a mistake or replace a damaged database, use *Restore* beside a backup in the console's *Overview*
([backups](backups.md#restoring-a-backup)). Without the console, name the dump; a backup on a bucket is downloaded into
`data/backups/` first:

```sh
docker compose stop photolibd
docker compose run --rm photolibd restore /data/backups/backup-20261021T030000Z.dump
docker compose up -d
```

What changed after the dump is lost, and every device syncs from scratch.

## Recover from storage

When the database is lost and no dump is left, photolibd rebuilds it from the libraries' manifests
([backups](backups.md#manifests-and-recovery-from-storage)). With `postgres/` empty:

```sh
docker compose up -d postgres                                    # an empty cluster with the password of .env
docker compose run --rm photolibd recover --from-storage local   # or the bucket's store
docker compose up -d
docker compose run --rm photolibd admin password-setup ann       # a link for each account to set its password
```

## Move the data directory

```sh
docker compose down
sudo rsync -aHAX --numeric-ids data/ /mnt/big/photolib/    # keeps owners and permissions
# set PHOTOLIB_DATA=/mnt/big/photolib in .env
docker compose up -d
```

photolibd starts only when the new directory's [instance marker](configuration.md#instance-marker) matches the
database, so a wrong path or an unmounted disk stops it and changes nothing. Delete the old copy once the libraries
look right. On NFS or SMB read [network filesystems](configuration.md#network-filesystems) first.

## Change the storage backend

New libraries and the backups go to a bucket through `placement` ([object storage](storage.md#placement)); a library
stays on the store it was created on. To move a bucket to another provider or bucket, copy it with its keys, markers
and each object's hash (rclone's `--metadata`), then point the same store at the copy:

```sh
rclone copy --metadata old:photolib new:photolib    # the bulk, while photolibd runs
docker compose stop photolibd
rclone sync --metadata old:photolib new:photolib    # the rest; deletes on new what old no longer has
# set the store's endpoint, bucket, region and keys to the new ones
docker compose up -d
```

The console's *Storage* shows the store online; keep the old bucket until a [scrub](console.md#integrity-and-backups)
has checked every original. To move the data directory, see above.

## Re-run thumbnails and ML

*Reprocess* in the console's *Overview*, for a library or a folder of it, reads metadata again, regenerates thumbnails
and previews, or detects faces again ([reprocessing](console.md#reprocessing)). *Jobs* shows the progress; pause a job
type there if it slows the server. Installing and changing models is [ML models](models.md).

## Rotate server secrets

| Secret | To rotate it |
|---|---|
| Database password, `POSTGRES_PASSWORD` in `.env` | `docker compose exec postgres psql -U photolib`, then `\password photolib`; set the same in `.env` and `docker compose up -d`. The PostgreSQL image reads `.env`'s only when it creates the cluster. |
| `metrics.token`, `ml.token` | A new value of 32 characters or more (`openssl rand -hex 16`); restart photolibd, then give it to Prometheus or the `ml` nodes. |
| A store's key, an OIDC client secret | Create a new one at the provider, set it, restart photolibd, check the console's *Storage* or a sign-in, then revoke the old one. |
| The OPAQUE key, `keys/opaque.key` | It cannot be rotated: every password is bound to it. If it leaked together with a database dump, someone can test guesses against that dump's passwords offline: have every account set a new password (*Password setup link*) and change it wherever they reused it. |

Caddy renews the TLS certificate itself.

## A user lost their recovery kit

Opening their private libraries without one of their unlock paths is impossible, by design: photolibd keeps only
wraps of their keys that it cannot open, so neither you, a backup nor Photolib's developers can help
([ADR-0255](../adr/0255-private-mode-keys-and-recovery.md)). While their password works, or a device is still signed
in, the libraries open: have them download what matters from there. Once the password and the kit are both gone and
no device is signed in, the private libraries are lost; a *Password setup link* gives them back their account and
standard libraries, never those. The app's six-monthly drill catches a lost kit before that.

## The disk is full

Uploads pause with `disk.low` below the console's floor, the `PhotolibDiskAlmostFull` [alert](monitoring.md#alerts)
fires over 90 %, and when PostgreSQL's disk fills it stops writing and `/readyz` fails. The console's *Storage* and
`df -h data postgres` say which. Free space without touching the libraries: `docker image prune`, `postgres/<old
major>` after a [PostgreSQL upgrade](upgrades.md#postgresql-major-upgrades), fewer `database.keep_backups`, and
people emptying their trash. Then move the data directory to a larger disk, or new libraries to a
[bucket](storage.md). Never delete files under `data/libraries` by hand: the scrub reports them missing. PostgreSQL
recovers by itself at `docker compose up -d`.

## Replace a failed node

A node of a scaled install that runs `api`, `scheduler`, `worker` or `ml` keeps nothing: start a replacement with
the same configuration and roles, and for `api` the same OPAQUE key file. The jobs the dead one held return to the
queue after their one-minute lease.

The only host, from the [admin-succession kit](backups.md#the-admin-succession-kit):

1. On the new host, unpack the bundle as [installing](install.md#install) shows, but instead of `setup.sh` put back
   `.env`, `compose.override.yaml` and `keys/` from the kit and `data/` from its
   [backup](backups.md#backing-up-the-originals), and make empty `postgres/`, `caddy/data` and `caddy/config` owned
   by `.env`'s `PUID:PGID`.
2. `docker compose up -d postgres`, then restore the newest backup into it as above, *Restore a database dump*. With
   no dump, *Recover from storage* instead.
3. `docker compose up -d`, and point the DNS record at the new host. Devices sync from scratch.
