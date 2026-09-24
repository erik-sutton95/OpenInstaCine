#!/usr/bin/env python3
"""Talk to the OpenInstaCine USB lab bridge. Mac stays off the camera AP."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request

DEFAULT_HOST = "fd09:43ed:4c2d::1"
HTTP_PORT = 18776
UDP_PORT = 18778


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


def usb_hosts() -> list[str]:
    hosts = [DEFAULT_HOST]
    try:
        text = subprocess.check_output(["ifconfig"], text=True)
    except (OSError, subprocess.CalledProcessError):
        return hosts
    for match in re.finditer(r"inet6 (fd[0-9a-f:]+)", text, re.I):
        ip = match.group(1).split("%")[0]
        if ip not in hosts:
            hosts.append(ip)
    return hosts


def discover(port: int = HTTP_PORT) -> tuple[str, str]:
    last = None
    for host in usb_hosts():
        url = f"http://[{host}]:{port}"
        try:
            payload = request(url + "/health", timeout=2)
            if payload.get("ok"):
                return url, host
            last = payload
        except Exception as error:
            last = error
            continue
    raise RuntimeError(f"OpenInstaCine lab bridge not reachable over USB: {last}")


def print_json(payload: dict) -> None:
    print(json.dumps(payload, indent=2, sort_keys=True))


async def recovery_command(host: str, enabled: bool | None) -> dict:
    import pathlib
    from luna_screen_live import ScreenControl, recovery_state

    library = pathlib.Path(__file__).resolve().parent.parent / ".local/luna-recovery-live/vendor/libkcp.dylib"
    log_lines: list[dict] = []

    def log(direction: str, data: bytes) -> None:
        log_lines.append({"direction": direction, "bytes": len(data)})

    control = ScreenControl(library, log)
    await control.connect(solicit=True, proxy=(host, UDP_PORT))
    config, _token = await control.get_configuration()
    before = recovery_state(config)
    result = {"ok": True, "before": before, "color_mode": config.get("iq_color_mode")}
    if enabled is None:
        result["config_ilog_lut"] = config.get("iq_ilog_lut")
        await control.close()
        return result
    actual = await control.set_recovery(enabled)
    result["after"] = recovery_state(actual)
    result["lut"] = actual.get("iq_ilog_lut")
    result["udp"] = log_lines[-6:]
    await control.close()
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url")
    parser.add_argument("--host")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("health")
    sub.add_parser("log")
    get_photo = sub.add_parser("photo-get")
    get_photo.add_argument("--types", default="35,72,73")
    get_photo.add_argument("--mode", type=int, default=7)
    set_photo = sub.add_parser("photo-set")
    set_photo.add_argument("field", type=int)
    set_photo.add_argument("value", type=int)
    set_photo.add_argument("--mode", type=int, default=7)
    command = sub.add_parser("command")
    command.add_argument("code", type=int)
    command.add_argument("body", nargs="?", default="")
    sub.add_parser("set73")
    sub.add_parser("recovery-get")
    recovery = sub.add_parser("recovery-set")
    recovery.add_argument("state", choices=("on", "off"))
    args = parser.parse_args()

    if args.url:
        url = args.url.rstrip("/")
        host = args.host or DEFAULT_HOST
    elif args.host:
        url, host = f"http://[{args.host}]:{HTTP_PORT}", args.host
    else:
        url, host = discover()

    if args.cmd == "health":
        print_json(request(url + "/health", timeout=5))
    elif args.cmd == "log":
        print_json(request(url + "/log", timeout=5))
    elif args.cmd == "photo-get":
        types = [int(part) for part in args.types.split(",") if part]
        print_json(request(url + "/photo/get", "POST", {"types": types, "mode": args.mode}))
    elif args.cmd == "photo-set":
        print_json(
            request(
                url + "/photo/set",
                "POST",
                {"field": args.field, "value": args.value, "mode": args.mode},
            )
        )
    elif args.cmd == "command":
        print_json(request(url + "/command", "POST", {"code": args.code, "body": args.body}))
    elif args.cmd == "set73":
        print_json(request(url + "/set73", "POST", {}, timeout=40))
    elif args.cmd in ("recovery-get", "recovery-set"):
        import asyncio

        enabled = None if args.cmd == "recovery-get" else args.state == "on"
        print_json(asyncio.run(recovery_command(host, enabled)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
