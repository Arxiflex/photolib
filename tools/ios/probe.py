#!/usr/bin/env python3
"""Upload sink and results table of the iOS backup probe (tools/ios/photokit_probe.sh); stdlib only.

    probe.py sink <port> <log>                  accept uploads, discard the bytes, log one JSON line per upload
    probe.py table <probe.jsonl> <sink.jsonl>   print the report's rows and the Upload-* headers iOS sent
"""
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def sink(port, log):
    lock = threading.Lock()

    class Sink(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"  # keeps connections open and answers Expect: 100-continue

        def do_GET(self):
            self.send_response(204)
            self.end_headers()

        def do_POST(self):
            start, left, received = time.monotonic(), int(self.headers.get("Content-Length", 0)), 0
            while left > 0:
                chunk = self.rfile.read(min(left, 1 << 20))
                if not chunk:
                    break
                left, received = left - len(chunk), received + len(chunk)
            entry = {"method": self.command, "path": self.path, "bytes": received,
                     "seconds": round(time.monotonic() - start, 3),
                     "headers": {k.lower(): v for k, v in self.headers.items() if k.lower().startswith("upload-")}}
            with lock, open(log, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry) + "\n")
            self.send_response(201)
            self.send_header("Content-Length", "0")
            self.end_headers()

        do_PUT = do_PATCH = do_POST

        def log_message(self, *args):
            pass

    ThreadingHTTPServer(("", port), Sink).serve_forever()


def rate(result):
    if not result["seconds"]:
        return "—"
    if result["bytes"]:
        return f"{result['bytes'] / result['seconds'] / 1e6:,.1f} MB/s"
    return f"{result['count'] / result['seconds']:,.0f}/s"


def table(probe, sink_log):
    with open(probe, encoding="utf-8") as f:
        results = [json.loads(line) for line in f if line.strip()]
    if not results:
        sys.exit(f"probe.py: no results in {probe}")
    print("| Metric | Count | Seconds | Rate |\n|---|---|---|---|")
    for r in results:
        print(f"| {r['metric']} | {r['count']:,} | {r['seconds']:.3f} | {rate(r)} |")
    headers = set()
    if os.path.exists(sink_log):
        with open(sink_log, encoding="utf-8") as f:
            headers = {f"{k}: {v}" for line in f if line.strip() for k, v in json.loads(line)["headers"].items()}
    print("\nUpload headers sent: " + ("; ".join(sorted(headers)) or "none"))


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "sink":
        sink(int(sys.argv[2]), sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "table":
        table(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
