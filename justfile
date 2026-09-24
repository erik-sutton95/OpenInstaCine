default:
    @just --list

# Copy current OpenPocketCine packages + native shells. Does not touch Luna adapters.
sync-openpocketcine:
    bash scripts/sync-openpocketcine.sh

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

# Research tooling checks; native gates are listed below.
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

# Camera AP must already be joined. Override transport with netcat on this Mac.
luna-preview seconds="20" transport="socket":
    /usr/bin/python3 tools/luna_tcp.py --seconds {{quote(seconds)}} --transport {{quote(transport)}}

# Mac live window; name is needed only on first setup, then saved privately.
luna-view name="":
    /usr/bin/python3 tools/luna_mac.py --name {{quote(name)}}

lab-check: check
    .venv/bin/python -m py_compile tools/luna_wire.py tools/luna_ble.py tools/luna_tcp.py tools/luna_screen_wire.py tools/luna_screen_capture.py
    .venv/bin/python tools/luna_ble.py --help > /dev/null
    .venv/bin/python tools/luna_tcp.py --help > /dev/null
    .venv/bin/python tools/luna_screen_capture.py --help > /dev/null
    /usr/bin/python3 -m py_compile tools/luna_mac.py tools/luna_tcp.py tools/luna_wire.py tools/ucd2.py
    .venv/bin/python -m unittest discover -s tools -p 'test_luna_*.py'

# Generate the iOS project (ios/project.yml, same layout as OpenPocketCine).
ios-generate:
    cd ios && xcodegen generate

# Compiles without signing or accessing a connected phone.
ios-build: ios-generate
    xcodebuild -project ios/OpenInstaCine.xcodeproj -scheme OpenInstaCine -destination 'generic/platform=iOS Simulator' -derivedDataPath .local/DD CODE_SIGNING_ALLOWED=NO build

# Development-signed build + install + launch on a USB iPhone (devicectl id).
ios-run device="B1138BFC-5392-56A1-93F1-5B722F7BA10F": ios-generate
    xcodebuild -project ios/OpenInstaCine.xcodeproj -scheme OpenInstaCine -destination 'generic/platform=iOS' -derivedDataPath .local/DDdev -allowProvisioningUpdates build
    xcrun devicectl device install app --device {{device}} .local/DDdev/Build/Products/Debug-iphoneos/OpenInstaCine.app
    xcrun devicectl device process launch --device {{device}} --activate --terminate-existing com.opencapture.openinstacine

ios-test *args: ios-generate
    #!/usr/bin/env bash
    set -euo pipefail
    device_id="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ && !found { print $2; found = 1 }')"
    xcodebuild -project ios/OpenInstaCine.xcodeproj -scheme OpenInstaCine -destination "platform=iOS Simulator,id=$device_id" -derivedDataPath .local/DD {{args}} test

# Drive a DEBUG build on the phone without XCUITest (screenshots, state, actions).
oic-remote *args:
    /usr/bin/python3 tools/oic_remote.py {{args}}

# Physical XC driver for the official Insta360 iOS app (lab captures). Needs UI Automation
# enabled on the phone; iOS asks for Face ID/passcode the first time automation mode starts.
luna-official-xc device:
    cd ios && xcodegen generate
    xcodebuild -project ios/OpenInstaCine.xcodeproj -scheme LunaOfficialCapture -destination 'platform=iOS,id={{device}}' -allowProvisioningUpdates -derivedDataPath .local/AppleDerivedData -maximum-test-execution-time-allowance 21600 -only-testing:LunaOfficialUITests/InteractiveDriver/testDriveOfficialInsta360 test

# USB lab bridge on the phone. Mac stays off the camera AP.
luna-lab-bridge *args:
    /usr/bin/python3 tools/luna_lab_bridge.py {{args}}

core-test:
    swift test
    swift test --package-path Adapters/Insta360Protocol

android-build:
    cd Apps/Android && ./gradlew :app:assembleDebug

android-check:
    cd Apps/Android && ./gradlew :monitor:testDebugUnitTest :luna-adapter:testDebugUnitTest :app:lintDebug :monitor:lintDebug :luna-adapter:lintDebug
