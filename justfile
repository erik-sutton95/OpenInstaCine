default:
    @just --list

# Requires Python 3.11+, nrfutil ble-sniffer, and Wireshark/tshark.
ble-scan label="advertisements" seconds="20":
    python3 tools/ble_lab.py scan {{quote(label)}} --seconds {{quote(seconds)}}

# Exact advertised name from a scan; starts following before the phone connects.
ble-follow name label="connection" seconds="180":
    python3 tools/ble_lab.py follow {{quote(label)}} --name {{quote(name)}} --seconds {{quote(seconds)}}

ble-report capture:
    python3 tools/ble_lab.py report {{quote(capture)}}

ble-mark session action:
    python3 tools/ble_lab.py mark {{quote(session)}} {{quote(action)}}

# Research tooling checks. App build/hardware gates will be added with the adapter.
check:
    python3 -m py_compile tools/ble_lab.py
    python3 tools/ble_lab.py --help > /dev/null
    python3 -m unittest discover -s tools -p 'test_ucd2.py'
    git diff --check
    git diff --cached --check

lab-setup:
    python3 -m venv .venv
    .venv/bin/python -m pip install -r requirements-lab.txt

# Exact advertised name. Only the first authorization requests a camera prompt.
luna-authorize name:
    .venv/bin/python tools/luna_ble.py --name {{quote(name)}} --authorize

luna-connect name:
    .venv/bin/python tools/luna_ble.py --name {{quote(name)}}

lab-check: check
    .venv/bin/python -m py_compile tools/luna_wire.py tools/luna_ble.py
    .venv/bin/python tools/luna_ble.py --help > /dev/null
    .venv/bin/python -m unittest discover -s tools -p 'test_luna_*.py'
