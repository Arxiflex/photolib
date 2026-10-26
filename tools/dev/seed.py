#!/usr/bin/env python3
"""Loads the dev seed set (testdata/seed) into the dev stack's S3 bucket as <library>/<file>.

seed.json declares users and libraries. Creating them needs the server API, which does not exist yet, so for now
they are only validated and decide which folder is a library. Settings come from the environment, filled from
tools/dev/.env. Standard library only.
"""
import datetime
import hashlib
import hmac
import http.client
import json
import os
import sys
import urllib.parse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SEED_DIR = os.path.join(ROOT, "testdata", "seed")
ENV_FILE = os.path.join(ROOT, "tools", "dev", ".env")
SETTINGS = ("AWS_ENDPOINT_URL", "AWS_REGION", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "S3_BUCKET")


def load_env_file(path, env):
    if not os.path.isfile(path):
        return
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            key, sep, value = line.strip().partition("=")
            if sep and not key.startswith("#"):
                env.setdefault(key, value)


def problems(manifest, files):
    found = []
    users = {user["id"] for user in manifest["users"]}
    libraries = {library["id"] for library in manifest["libraries"]}
    for library in manifest["libraries"]:
        if library["owner"] not in users:
            found.append(f"library {library['id']}: unknown owner {library['owner']}")
        found += [f"library {library['id']}: unknown member {m}" for m in library["members"] if m not in users]
    found += [f"library {lib} has no media folder in {SEED_DIR}" for lib in sorted(libraries - set(files))]
    found += [f"media folder {lib} is not a library in seed.json" for lib in sorted(set(files) - libraries)]
    return found


def hmac_sha256(key, message):
    return hmac.new(key, message.encode(), hashlib.sha256).digest()


def authorization(method, path, headers, access_key, secret_key, region):
    """The AWS Signature Version 4 Authorization header for an S3 request; headers must include x-amz-date."""
    names = sorted(headers)
    canonical = "\n".join(
        [method, path, ""]
        + [f"{name}:{headers[name].strip()}" for name in names]
        + ["", ";".join(names), headers["x-amz-content-sha256"]]
    )
    date = headers["x-amz-date"][:8]
    scope = f"{date}/{region}/s3/aws4_request"
    to_sign = "\n".join(["AWS4-HMAC-SHA256", headers["x-amz-date"], scope, hashlib.sha256(canonical.encode()).hexdigest()])
    key = hmac_sha256(hmac_sha256(hmac_sha256(hmac_sha256(("AWS4" + secret_key).encode(), date), region), "s3"), "aws4_request")
    signature = hmac.new(key, to_sign.encode(), hashlib.sha256).hexdigest()
    return f"AWS4-HMAC-SHA256 Credential={access_key}/{scope},SignedHeaders={';'.join(names)},Signature={signature}"


def put_object(env, key, body):
    endpoint = urllib.parse.urlsplit(env["AWS_ENDPOINT_URL"])
    path = "/" + urllib.parse.quote(f"{env['S3_BUCKET']}/{key}", safe="/-_.~")
    headers = {
        "content-type": "image/jpeg",
        "host": endpoint.netloc,
        "x-amz-content-sha256": hashlib.sha256(body).hexdigest(),
        "x-amz-date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
    }
    auth = authorization("PUT", path, headers, env["AWS_ACCESS_KEY_ID"], env["AWS_SECRET_ACCESS_KEY"], env["AWS_REGION"])
    connection = (http.client.HTTPSConnection if endpoint.scheme == "https" else http.client.HTTPConnection)(endpoint.netloc)
    try:
        connection.request("PUT", path, body, {**headers, "Authorization": auth})
        response = connection.getresponse()
        response.read()
    finally:
        connection.close()
    if response.status != 200:
        raise RuntimeError(f"S3 rejected {key}: HTTP {response.status}")


def main(env=None):
    if env is None:
        env = dict(os.environ)
        load_env_file(ENV_FILE, env)
    missing = [name for name in SETTINGS if not env.get(name)]
    if missing:
        print(f"seed: missing {', '.join(missing)}; run `just bootstrap` to create tools/dev/.env", file=sys.stderr)
        return 1
    with open(os.path.join(SEED_DIR, "seed.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    files = {
        entry: sorted(os.listdir(os.path.join(SEED_DIR, entry)))
        for entry in sorted(os.listdir(SEED_DIR))
        if os.path.isdir(os.path.join(SEED_DIR, entry))
    }
    found = problems(manifest, files)
    if found:
        print("seed: " + "\nseed: ".join(found), file=sys.stderr)
        return 1
    count = 0
    try:
        for library, names in files.items():
            for name in names:
                with open(os.path.join(SEED_DIR, library, name), "rb") as handle:
                    put_object(env, f"{library}/{name}", handle.read())
                count += 1
    except OSError as error:
        print(f"seed: cannot reach S3 at {env['AWS_ENDPOINT_URL']} ({error}); is the stack up? run `just bootstrap`", file=sys.stderr)
        return 1
    except RuntimeError as error:
        print(f"seed: {error}", file=sys.stderr)
        return 1
    print(f"seed: loaded {count} media files for {len(files)} libraries into s3://{env['S3_BUCKET']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
