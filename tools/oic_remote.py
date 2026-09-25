#!/usr/bin/env python3
"""Drive a DEBUG OpenInstaCine build on a USB iPhone (DebugRemote, TCP 18780 over CoreDevice).

  tools/oic_remote.py state
  tools/oic_remote.py do '{"action":"iso","value":400}'
  tools/oic_remote.py shot out.png      # UIKit snapshot of the key window
  tools/oic_remote.py frame out.jpg     # last decoded live frame (VT path)
  tools/oic_remote.py log
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.request

DEVICE = os.environ.get("OIC_DEVICE", "B1138BFC-5392-56A1-93F1-5B722F7BA10F")


def base() -> str:
    if os.environ.get("OIC_URL"):
        return os.environ["OIC_URL"]
    out = subprocess.run(["xcrun", "devicectl", "device", "info", "details", "--device", DEVICE],
                         capture_output=True, text=True).stdout
    match = re.search(r"tunnelIPAddress: (\S+)", out)
    if not match:
        sys.exit("no CoreDevice tunnel")
    return f"http://[{match.group(1)}]:18780"


def call(path: str, body: dict | None = None, timeout: float = 60) -> bytes:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base() + path, data=data, method="POST" if data else "GET")
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read()


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    if cmd == "state":
        print(call("/state").decode())
    elif cmd == "log":
        print(call("/log").decode())
    elif cmd == "do":
        print(call("/action", json.loads(sys.argv[2]), timeout=180).decode())
    elif cmd in ("shot", "frame"):
        data = call("/screenshot" if cmd == "shot" else "/frame")
        with open(sys.argv[2], "wb") as handle:
            handle.write(data)
        print(sys.argv[2], len(data))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
