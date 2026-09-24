#!/usr/bin/env python3
"""Lab: GET/SET photography option 73 (COLOR_RECOVERY_SWITCH) on TCP 6666.

Requires the official Insta360 app to be quit and the Mac already on the camera
AP (192.168.42.1). Does not print credentials. Writes a private capture folder.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
from datetime import datetime, timezone
from pathlib import Path

from luna_tcp import PREFIX, Session
from luna_wire import blob, color_recovery_set, fields, integer, one, photography_get, photography_set

ROOT = Path(__file__).resolve().parent.parent
PHOTO = 9
PHOTO_GET = 10
COLOR_MODE = 35
I_LOG = 72
RECOVERY = 73


def utc():
    return datetime.now(timezone.utc).isoformat()


def options_map(body: bytes) -> dict[int, int | bytes]:
    nested = one(body, 2, b"")
    if not isinstance(nested, bytes):
        return {}
    result = {}
    for field, wire, value in fields(nested):
        result[field] = value
    return result


def present(values: dict[int, int | bytes], number: int) -> str:
    if number not in values:
        return "omitted"
    value = values[number]
    if isinstance(value, bytes):
        return value.hex()
    return str(value)


async def probe(folder: Path, identity: str, host: str) -> dict:
    summary = {"started_utc": utc(), "state": "tcp-connect", "host": host}
    reader, writer = await asyncio.wait_for(asyncio.open_connection(host, 6666), 6)
    session = Session(reader, writer, folder, record_media=False)
    tasks = [asyncio.create_task(session.receive())]
    log = []
    try:
        summary["state"] = "greeting"
        await session.send(PREFIX)
        await asyncio.wait_for(session.greeting.wait(), 8)
        if session.failure:
            raise session.failure
        tasks.append(asyncio.create_task(session.keepalive()))
        summary["state"] = "authorization"
        encoded = identity.encode()
        auth = await session.request(39, blob(1, encoded) + integer(2, 1) + blob(3, encoded))
        summary["authorization_status"] = one(auth, 1, 0)
        if summary["authorization_status"] != 0:
            raise RuntimeError("Saved identity is not authorized over TCP")

        async def step(label: str, code: int, body: bytes) -> bytes:
            reply = await session.request(code, body)
            values = options_map(reply) if code in (PHOTO, PHOTO_GET) else {}
            row = {
                "utc": utc(),
                "label": label,
                "code": code,
                "color_mode": present(values, COLOR_MODE),
                "i_log_switch": present(values, I_LOG),
                "recovery_73": present(values, RECOVERY),
                "nested_fields": sorted(values),
                "reply_hex": reply.hex(),
            }
            log.append(row)
            print(f"{label}: color={row['color_mode']} i_log={row['i_log_switch']} "
                  f"recovery={row['recovery_73']} fields={row['nested_fields']}", flush=True)
            return reply

        summary["state"] = "get-initial"
        await step("GET 35/72/73", PHOTO_GET, photography_get([COLOR_MODE, I_LOG, RECOVERY]))
        initial = log[-1]
        if initial["color_mode"] not in ("2", "omitted"):
            summary["state"] = "set-ilog"
            await session.request(PHOTO, photography_set([COLOR_MODE], integer(COLOR_MODE, 2)))
            await step("GET after I-Log SET", PHOTO_GET, photography_get([COLOR_MODE, I_LOG, RECOVERY]))

        for enabled, name in ((True, "SET 73 on"), (False, "SET 73 off"), (True, "SET 73 on again")):
            summary["state"] = name
            await session.request(PHOTO, color_recovery_set(enabled))
            await asyncio.sleep(0.4)
            await step(f"GET after {name}", PHOTO_GET, photography_get([COLOR_MODE, I_LOG, RECOVERY]))

        ons = [row["recovery_73"] for row in log if row["label"].startswith("GET after SET 73 on")]
        offs = [row["recovery_73"] for row in log if row["label"] == "GET after SET 73 off"]
        summary["recovery_after_on"] = ons
        summary["recovery_after_off"] = offs
        proven = any(v == "1" for v in ons) and any(v in ("0", "omitted") for v in offs)
        summary["set73_proven"] = proven
        summary["state"] = "proven" if proven else "inconclusive"
        return summary
    except Exception as error:
        summary.update(state="error", error_type=type(error).__name__, error=str(error)[:400])
        print("FAILED:", summary.get("error_type"), summary.get("error"), flush=True)
        return summary
    finally:
        (folder / "set73-log.json").write_text(json.dumps(log, indent=2) + "\n")
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        session.writer.close()
        try:
            await asyncio.wait_for(session.writer.wait_closed(), 3)
        except Exception:
            pass
        session.close_files()
        summary["finished_utc"] = utc()
        (folder / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="192.168.42.1")
    args = parser.parse_args()
    identity = json.loads((ROOT / ".local/luna-client-identity.json").read_text())["authorization_id"]
    os.umask(0o077)
    folder = ROOT / "captures" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-luna-set73")
    folder.mkdir(parents=True, mode=0o700)
    print("Session:", folder.relative_to(ROOT), flush=True)
    summary = asyncio.run(probe(folder, identity, args.host))
    print("Result:", summary["state"], "proven=" + str(summary.get("set73_proven")), flush=True)
    return 0 if summary.get("set73_proven") else 1


if __name__ == "__main__":
    raise SystemExit(main())
