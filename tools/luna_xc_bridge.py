#!/usr/bin/env python3
"""Talk to the on-device Insta360 XC driver over the CoreDevice IPv6 tunnel."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

DEVICE = os.environ.get("LUNA_XC_DEVICE", "B1138BFC-5392-56A1-93F1-5B722F7BA10F")


def tunnel_url() -> str:
    """CoreDevice tunnel IPv6 changes on every reconnect; ask devicectl."""
    if os.environ.get("LUNA_XC_URL"):
        return os.environ["LUNA_XC_URL"]
    out = subprocess.run(["xcrun", "devicectl", "device", "info", "details", "--device", DEVICE],
                         capture_output=True, text=True).stdout
    match = re.search(r"tunnelIPAddress: (\S+)", out)
    if not match:
        raise SystemExit("no CoreDevice tunnel; is the iPhone connected and unlocked?")
    return f"http://[{match.group(1)}]:18777"


def request(url: str, method: str = "GET", body: dict | None = None, timeout: float = 30) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        payload = error.read().decode()
        try:
            return json.loads(payload)
        except json.JSONDecodeError as decode_error:
            raise RuntimeError(f"HTTP {error.code}: {payload[:400]}") from decode_error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=None)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("health")
    sub.add_parser("tree")
    command = sub.add_parser("command")
    command.add_argument("payload", help="JSON object, e.g. {\"action\":\"tap\",\"label\":\"ISO\"}")
    sub.add_parser("stop")
    shot = sub.add_parser("screenshot")
    shot.add_argument("path")
    args = parser.parse_args()
    args.url = args.url or tunnel_url()
    if args.cmd == "health":
        print(json.dumps(request(args.url + "/health", timeout=5), indent=2))
    elif args.cmd == "tree":
        result = request(args.url + "/tree", timeout=40)
        for key in ("buttons", "texts", "images", "cells", "switches", "state", "label"):
            if key in result:
                print(f"{key}: {result[key]}")
        print("\n--- tree ---\n")
        print(result.get("tree", ""))
    elif args.cmd == "command":
        payload = json.loads(args.payload)
        result = request(args.url + "/command", "POST", payload, timeout=60)
        for key in ("ok", "action", "error", "state", "buttons", "texts"):
            if key in result:
                print(f"{key}: {result[key]}")
        if "tree" in result and not result.get("ok", True):
            print(result["tree"])
    elif args.cmd == "screenshot":
        result = request(args.url + "/screenshot", timeout=30)
        with open(args.path, "wb") as handle:
            handle.write(base64.b64decode(result["png"]))
        print(args.path)
    elif args.cmd == "stop":
        print(json.dumps(request(args.url + "/stop", "POST", {}, timeout=10), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
