#!/usr/bin/env python3
"""Local BLE capture, action markers, and transport-neutral ATT extraction."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / "captures"


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def executable(name):
    found = shutil.which(name)
    if not found and name == "tshark":
        candidate = Path("/Applications/Wireshark.app/Contents/MacOS/tshark")
        if candidate.is_file():
            found = str(candidate)
    if not found:
        raise ValueError(f"Required tool is missing: {name}")
    return found


def private_path(value):
    path = Path(value).expanduser().resolve()
    if not path.is_relative_to(CAPTURES.resolve()) or path == CAPTURES.resolve():
        raise ValueError("Use a path inside this repository's gitignored captures/ directory.")
    return path


def dump_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def choose_port(given):
    if given:
        return given
    listing = subprocess.run([executable("tshark"), "-D"], check=True,
                             capture_output=True, text=True).stdout
    ports = re.findall(r"^\d+\. (\S+) \(nRF Sniffer for Bluetooth LE\)", listing, re.M)
    if len(ports) != 1:
        raise ValueError("Cannot select one nRF sniffer. Use --port with its serial port.")
    return ports[0]


def stop_capture(process):
    if process.poll() is not None:
        return
    # Stop the nrfutil process group, including its BLE plugin child.
    import os
    os.killpg(process.pid, signal.SIGINT)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()


def capture(args):
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}", args.label):
        raise ValueError("Label must be 1–80 letters, digits, hyphens, or underscores.")
    if not 1 <= args.seconds <= 3600:
        raise ValueError("Capture duration must be 1–3600 seconds.")
    if args.address and not re.fullmatch(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}", args.address):
        raise ValueError("Address must have the form AA:BB:CC:DD:EE:FF.")
    command = [executable("nrfutil"), "ble-sniffer", "sniff", "--port", choose_port(args.port),
               "--scan-follow-rsp", "--scan-follow-aux"]
    if args.operation == "scan":
        command += ["--only-advertising"]
    elif args.address:
        command += ["--follow", args.address]
    else:
        command += ["--follow-by-name", args.name]
    if args.coded:
        command += ["--coded"]
    session = CAPTURES / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + "-" + args.label)
    session.mkdir(parents=True)
    packet_file = session / "ble.pcap"
    command += ["--output-pcap-file", str(packet_file)]
    metadata = {"started_utc": utc_now(), "requested_seconds": args.seconds,
                "operation": args.operation, "command": command,
                "camera_model": "Luna Ultra (operator identification pending)",
                "firmware": None, "phone_os": None, "official_app_version": None,
                "camera_state": "record in actions.jsonl", "pairing_state": "unknown",
                "sniffer_version": subprocess.run(
                    [command[0], "ble-sniffer", "--version"], check=True,
                    capture_output=True, text=True).stdout.strip()}
    dump_json(session / "metadata.json", metadata)
    print(f"Session: {session.relative_to(ROOT)}", flush=True)
    print("Starting passive capture; confirm packet count afterward. Ctrl-C stops early.", flush=True)
    with (session / "sniffer.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            process.wait(timeout=args.seconds)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            pass
        finally:
            stop_capture(process)
    metadata.update({"finished_utc": utc_now(), "exit_code": process.returncode})
    if packet_file.exists():
        metadata.update({"capture_bytes": packet_file.stat().st_size,
                         "capture_sha256": sha256(packet_file)})
    dump_json(session / "metadata.json", metadata)
    if not packet_file.exists() or packet_file.stat().st_size <= 24:
        raise ValueError(f"No packet data captured. Inspect {session.relative_to(ROOT)}/sniffer.log.")
    if process.returncode not in (0, -signal.SIGINT, 128 + signal.SIGINT):
        raise ValueError(f"Sniffer failed ({process.returncode}); partial capture retained in {session.relative_to(ROOT)}.")
    print(f"Saved {packet_file.relative_to(ROOT)} ({packet_file.stat().st_size} bytes).")


def marker(args):
    session = private_path(args.session)
    if not session.is_dir():
        raise ValueError("Session directory does not exist.")
    with (session / "actions.jsonl").open("a") as target:
        target.write(json.dumps({"utc": utc_now(), "action": args.action}) + "\n")
    print("Action timestamp saved.")


ATT_FIELDS = ["frame.number", "frame.time_epoch", "frame.time_relative", "frame.interface_id",
              "bluetooth.src", "bluetooth.dst", "hci_h4.direction", "frame.p2p_dir",
              "bthci_acl.chandle", "btle.access_address", "nordic_ble.direction",
              "nordic_ble.crcok", "nordic_ble.encrypted", "nordic_ble.micok",
              "btatt.opcode", "btatt.handle",
              "btatt.uuid16", "btatt.uuid128", "btatt.service_uuid16", "btatt.service_uuid128",
              "btatt.characteristic_uuid16", "btatt.characteristic_uuid128",
              "btatt.characteristic_properties", "btatt.value"]


def extract(tshark, source, output, display_filter, fields=None):
    command = [tshark, "-n", "-2", "-r", str(source), "-Y", display_filter]
    if fields:
        command += ["-T", "fields", "-E", "header=y", "-E", "quote=d", "-E", "occurrence=a"]
        for field in fields:
            command += ["-e", field]
    else:
        command += ["-T", "json"]
    with output.open("w") as target:
        result = subprocess.run(command, stdout=target, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise ValueError(f"tshark extraction failed: {result.stderr.strip()}")


def report(args):
    source = private_path(args.capture)
    if not source.is_file():
        raise ValueError("Capture file does not exist.")
    tshark = executable("tshark")
    output = source.parent / (source.stem + "-report-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    output.mkdir()
    extract(tshark, source, output / "advertisements.tsv", "btle.advertising_address",
            ["frame.number", "frame.time_epoch", "btle.advertising_address",
             "btle.advertising_header.randomized_tx", "btcommon.eir_ad.entry.device_name",
             "btcommon.eir_ad.entry.company_id", "btcommon.eir_ad.entry.uuid_16",
             "btcommon.eir_ad.entry.uuid_128", "nordic_ble.rssi", "nordic_ble.flags"])
    extract(tshark, source, output / "att.tsv", "btatt", ATT_FIELDS)
    # JSON retains relationships between multiple discovery attributes in one PDU.
    extract(tshark, source, output / "bluetooth.json", "btatt || btsmp || btle.control_opcode || bthci_cmd || bthci_evt")
    extract(tshark, source, output / "link.tsv", "btle.data_header || btle.control_opcode || btsmp",
            ["frame.number", "frame.time_epoch", "btle.access_address", "btle.control_opcode",
             "nordic_ble.flags", "btle.data_header.length"])
    with (output / "att.tsv").open() as rows:
        att_count = sum(1 for _ in rows) - 1
    dump_json(output / "manifest.json", {"source": str(source.relative_to(ROOT)),
              "source_sha256": sha256(source), "generated_utc": utc_now(),
              "att_packets": att_count, "tshark_version": subprocess.run(
                  [tshark, "--version"], check=True, capture_output=True, text=True).stdout.splitlines()[0]})
    print(f"Report: {output.relative_to(ROOT)}; ATT packets: {att_count}.")
    print("Raw payloads and identifiers remain in captures/. Review before publishing findings.")
    if att_count == 0:
        print("No decoded ATT: check target selection, capture start, link encryption, and logger type.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="operation", required=True)
    for operation in ("scan", "follow"):
        child = sub.add_parser(operation)
        child.add_argument("label")
        child.add_argument("--seconds", type=int, default=20 if operation == "scan" else 180)
        child.add_argument("--port")
        child.add_argument("--coded", action="store_true")
        if operation == "follow":
            target = child.add_mutually_exclusive_group(required=True)
            target.add_argument("--address")
            target.add_argument("--name")
        else:
            child.set_defaults(address=None, name=None)
        child.set_defaults(run=capture)
    child = sub.add_parser("mark")
    child.add_argument("session")
    child.add_argument("action")
    child.set_defaults(run=marker)
    child = sub.add_parser("report")
    child.add_argument("capture")
    child.set_defaults(run=report)
    args = parser.parse_args()
    try:
        args.run(args)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    main()
