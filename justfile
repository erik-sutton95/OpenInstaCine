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
    python3 -m unittest discover -s tools -p 'test_*.py'
    git diff --check
    git diff --cached --check
