#!/usr/bin/env python3
"""Mac test launcher: BLE credentials → camera Wi-Fi → live preview window.

Uses system Python for TCP and the project venv for BLE. Closing the window
stops preview, then restores automatic Wi-Fi selection if this launch changed it.
No camera credentials are printed. This is a lab viewer, not the native app.
"""

import argparse
import fcntl
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def command(arguments, timeout=30):
    return subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)


def wifi_address():
    return command(["/usr/sbin/ipconfig", "getifaddr", "en0"]).stdout.strip()


def save_private(path, value):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as output:
        os.fchmod(output.fileno(), 0o600)
        json.dump(value, output, indent=2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", help="Exact BLE advertised name; saved privately for future launches")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This launcher is for macOS")
    local = ROOT / ".local"
    local.mkdir(mode=0o700, exist_ok=True)
    config_path = local / "luna-mac.json"
    name = args.name
    if not name and config_path.exists():
        name = json.loads(config_path.read_text()).get("advertised_name")
    if not name:
        parser.error("Supply --name once with the camera's exact advertised name")
    python = ROOT / ".venv/bin/python"
    if not python.exists():
        parser.error("Run just lab-setup first")
    lock = (local / "luna-viewer.lock").open("a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("The Luna viewer launcher is already running.")
        return 0
    save_private(config_path, {"advertised_name": name})
    print("Connecting to Luna over Bluetooth…", flush=True)
    # --authorize only prompts when this identity is not already authorized.
    result = subprocess.run([str(python), str(ROOT / "tools/luna_ble.py"), "--name", name, "--authorize"])
    if result.returncode:
        print("Camera connection failed. Keep Luna awake and the Insta360 app disconnected.", flush=True)
        return result.returncode

    credentials = json.loads((local / "luna-wifi.json").read_text())
    ssid = credentials["ssid"]
    preferred_result = command(["/usr/sbin/networksetup", "-listpreferredwirelessnetworks", "en0"])
    if preferred_result.returncode:
        print("Could not read Wi-Fi state; leaving the current network unchanged.", flush=True)
        return 1
    preferred = [line.strip() for line in preferred_result.stdout.splitlines()[1:]]
    prior_address = wifi_address()
    was_on_camera_subnet = prior_address.startswith("192.168.42.")
    changed_network = False
    player = None
    try:
        print("Joining the Luna's Wi-Fi…", flush=True)
        changed_network = not was_on_camera_subnet
        joined = command(["/usr/sbin/networksetup", "-setairportnetwork", "en0", ssid, credentials["password"]])
        save_private(local / "viewer-network.json", {"prior_address": prior_address,
                     "camera_profile_preexisting": ssid in preferred, "join_exit": joined.returncode,
                     "join_stdout": joined.stdout, "join_stderr": joined.stderr})
        if joined.returncode or joined.stdout.strip() or joined.stderr.strip():
            print("Wi-Fi association did not complete; see the private network log.", flush=True)
            return 1
        deadline = time.monotonic() + 20
        while not wifi_address().startswith("192.168.42."):
            if time.monotonic() > deadline:
                print("Timed out waiting for the camera's network address.", flush=True)
                return 1
            time.sleep(0.5)
        print("Opening live preview. Close its window or press Q to disconnect.", flush=True)
        player = subprocess.Popen(["/usr/bin/python3", str(ROOT / "tools/luna_tcp.py"), "--view", "--seconds", "0"])
        return player.wait()
    except KeyboardInterrupt:
        if player and player.poll() is None:
            player.send_signal(signal.SIGINT)
            try:
                player.wait(timeout=15)
            except subprocess.TimeoutExpired:
                player.terminate()
        return 130
    finally:
        if changed_network:
            print("Restoring Wi-Fi network selection…", flush=True)
            if ssid not in preferred:
                command(["/usr/sbin/networksetup", "-removepreferredwirelessnetwork", "en0", ssid])
            for state in ("off", "on"):
                command(["/usr/sbin/networksetup", "-setairportpower", "en0", state])
            save_private(local / "viewer-network-restoration.json", {
                "restoration_requested": True, "prior_address": prior_address,
                "removed_temporary_profile": ssid not in preferred})


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
