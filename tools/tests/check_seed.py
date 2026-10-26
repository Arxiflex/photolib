#!/usr/bin/env python3
"""Check the seed fixtures and loader against a local fake S3 server."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import re
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

from checklib import ROOT, check, finish

SEED_DIR = os.path.join(ROOT, "testdata", "seed")


def load_loader():
    spec = importlib.util.spec_from_file_location("seed", os.path.join(ROOT, "tools", "dev", "seed.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def seed_files():
    found = {}
    for library in sorted(os.listdir(SEED_DIR)):
        folder = os.path.join(SEED_DIR, library)
        if os.path.isdir(folder):
            found[library] = sorted(os.listdir(folder))
    return found


def check_data():
    path = os.path.join(SEED_DIR, "seed.json")
    if not check(os.path.isfile(path), "testdata/seed/seed.json exists"):
        return
    with open(path, encoding="utf-8") as handle:
        manifest = json.load(handle)
    users = {user["id"]: user for user in manifest["users"]}
    libraries = {library["id"]: library for library in manifest["libraries"]}
    files = seed_files()

    check(len(users) == len(manifest["users"]), "user ids are unique")
    check(len(libraries) == len(manifest["libraries"]), "library ids are unique")
    check(len(users) >= 3 and any(user["admin"] for user in users.values()), "at least 3 users, one of them an admin")
    check(all(re.fullmatch(r"[^@\s]+@example\.test", user["email"]) for user in users.values()), "emails use the reserved example.test domain")
    check(len(libraries) >= 2, "at least 2 libraries")
    check(all(lib["owner"] in users and set(lib["members"]) <= set(users) for lib in libraries.values()), "owners and members are known users")
    check(any(lib["members"] for lib in libraries.values()), "one library is shared with a member")
    check(set(files) == set(libraries), "every library has a media folder and every media folder a library")

    sizes = []
    for library, names in files.items():
        check(len(names) >= 3, f"library {library} holds at least 3 media files")
        for name in names:
            with open(os.path.join(SEED_DIR, library, name), "rb") as handle:
                data = handle.read()
            sizes.append(len(data))
            check(data[:3] == b"\xff\xd8\xff", f"{library}/{name} is a JPEG")
            check(re.search(rb"Exif\x00\x00", data) and re.search(rb"20\d\d:\d\d:\d\d \d\d:\d\d:\d\d\x00", data), f"{library}/{name} carries an EXIF capture date")
    check(sizes and max(sizes) <= 64 * 1024 and sum(sizes) <= 512 * 1024, "the media set is small (files <= 64 KiB, total <= 512 KiB)")


def check_signature(loader):
    # The worked example from the AWS Signature Version 4 documentation ("GET Object" with a Range header).
    headers = {
        "host": "examplebucket.s3.amazonaws.com",
        "range": "bytes=0-9",
        "x-amz-content-sha256": hashlib.sha256(b"").hexdigest(),
        "x-amz-date": "20130524T000000Z",
    }
    got = loader.authorization("GET", "/test.txt", headers, "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", "us-east-1")
    want = (
        "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,"
        "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,"
        "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
    )
    check(got == want, "SigV4 signature matches the AWS documentation example")


class FakeS3(BaseHTTPRequestHandler):
    def do_PUT(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        self.server.requests.append((self.path, dict(self.headers), body))
        self.send_response(self.server.status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


def run_loader(loader, env):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        status = loader.main(env)
    return status, out.getvalue(), err.getvalue()


def check_loader(loader):
    server = HTTPServer(("127.0.0.1", 0), FakeS3)
    server.requests, server.status = [], 200
    threading.Thread(target=server.serve_forever, daemon=True).start()
    env = {
        "AWS_ENDPOINT_URL": f"http://127.0.0.1:{server.server_port}",
        "AWS_REGION": "garage",
        "AWS_ACCESS_KEY_ID": "GKtest",
        "AWS_SECRET_ACCESS_KEY": "secret",
        "S3_BUCKET": "photolib-dev",
    }
    expected = {f"/photolib-dev/{lib}/{name}": name for lib, names in seed_files().items() for name in names}

    status, out, _ = run_loader(loader, env)
    check(status == 0, "the loader succeeds against a reachable store")
    check(sorted(path for path, _, _ in server.requests) == sorted(expected), "every media file is uploaded once as <bucket>/<library>/<file>")
    for path, headers, body in server.requests:
        library, name = path.split("/")[2:]
        with open(os.path.join(SEED_DIR, library, name), "rb") as handle:
            check(body == handle.read(), f"{path} is uploaded unchanged")
        check(headers["x-amz-content-sha256"] == hashlib.sha256(body).hexdigest(), f"{path} declares its payload hash")
        check(headers["Authorization"].startswith("AWS4-HMAC-SHA256 Credential=GKtest/") and "/garage/s3/aws4_request," in headers["Authorization"], f"{path} is signed for the configured region")
    check(f"{len(expected)} media files" in out and "2 libraries" in out, "the loader reports what it loaded")

    server.status = 403
    status, _, err = run_loader(loader, env)
    check(status == 1 and "403" in err, "a rejected upload fails the loader and names the status")

    server.shutdown()
    server.server_close()
    status, _, err = run_loader(loader, env)
    check(status == 1 and "bootstrap" in err, "an unreachable store fails the loader and points at the stack")

    status, _, err = run_loader(loader, {})
    check(status == 1 and "AWS_ENDPOINT_URL" in err, "missing settings fail the loader and name the variable")


def check_env_file(loader):
    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, ".env")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("# comment\n\nA=1\nB=two=2\nC=from-file\n")
        env = {"C": "from-env"}
        loader.load_env_file(path, env)
        check(env == {"A": "1", "B": "two=2", "C": "from-env"}, "the .env file fills only the settings the environment lacks")
        loader.load_env_file(os.path.join(folder, "missing"), env)
        check(True, "a missing .env file is not an error")


def check_validation(loader):
    manifest = {
        "users": [{"id": "a", "admin": True}],
        "libraries": [{"id": "l", "owner": "a", "members": []}],
    }
    check(loader.problems(manifest, {"l": ["x.jpg"]}) == [], "a consistent manifest has no problems")
    check(loader.problems({**manifest, "libraries": [{"id": "l", "owner": "zed", "members": []}]}, {"l": ["x.jpg"]}), "an unknown owner is reported")
    check(loader.problems(manifest, {}), "a library without a media folder is reported")
    check(loader.problems(manifest, {"l": ["x.jpg"], "stray": ["y.jpg"]}), "a media folder without a library is reported")


check_data()
loader_ready = check(os.path.isfile(os.path.join(ROOT, "tools", "dev", "seed.py")), "tools/dev/seed.py exists")
if loader_ready:
    module = load_loader()
    check_signature(module)
    check_loader(module)
    check_env_file(module)
    check_validation(module)

finish()
