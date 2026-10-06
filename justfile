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

# Research tooling checks; native gates are listed below.
check:
    python3 -m py_compile tools/ble_lab.py
    python3 tools/ble_lab.py --help > /dev/null
    python3 -m unittest discover -s tools -p 'test_ucd2.py'
    bash tools/sentry-test.sh
    ./scripts/ios-release-notes-check.sh
    ./scripts/android-release-notes-check.sh
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
    swift test --package-path ../OpenCine --filter Insta360

android-build:
    cd Apps/Android && JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}" ./gradlew :app:assembleDebug

android-check:
    cd Apps/Android && JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}" ./gradlew :app:assembleDebug :monitor:testDebugUnitTest :app:lintDebug :monitor:lintDebug

# --- Release (docs/RELEASE.md, docs/testflight-ci.md, docs/android-play-ci.md) ---

# Offline Sentry release-tooling checks. No network, no uploads.
sentry-test:
    bash tools/sentry-test.sh

testflight-notes:
    ./scripts/ios-release-notes-check.sh
    ./scripts/ios-release-notes-test.sh
    ./scripts/ios-release-notes.sh

android-play-notes:
    ./scripts/android-release-notes-check.sh
    ./scripts/android-release-notes-test.sh
    ./scripts/android-release-notes.sh

tester-notes-window:
    ./scripts/tester-notes-window.sh

ios-version:
    @sed -n 's/^MARKETING_VERSION = /Version: /p; s/^CURRENT_PROJECT_VERSION = /Build: /p' ios/Config/Version.xcconfig

android-version:
    @sed -n 's/^openinstacine.versionName=/Version: /p; s/^openinstacine.versionCode=/Build: /p' Apps/Android/gradle.properties

# Refresh ios/Package.resolved after changing packages in ios/project.yml; commit the result.
ios-resolve: ios-generate
    xcodebuild -resolvePackageDependencies -project ios/OpenInstaCine.xcodeproj -scheme OpenInstaCine
    cp ios/OpenInstaCine.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved ios/Package.resolved

# Local iOS builds: SENTRY_DSN_IOS from .local/reliability.properties -> ignored Reliability.local.xcconfig.
ios-local-dsn:
    SENTRY_DSN_IOS="$(sed -n 's/^SENTRY_DSN_IOS=//p' .local/reliability.properties)" python3 tools/sentry-dsn-xcconfig.py --out ios/OpenInstaCine/Reliability.local.xcconfig --require

# Signed Play bundle with the upload key from .local/play-signing.env. VERSION_CODE=n overrides the floor.
android-bundle:
    #!/usr/bin/env bash
    set -euo pipefail
    set -a; source .local/play-signing.env; set +a
    cd Apps/Android
    JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}" ./gradlew bundleRelease ${VERSION_CODE:+-PversionCode="$VERSION_CODE"}
    echo "AAB: Apps/Android/app/build/outputs/bundle/release/app-release.aab"

# Sideload APK for a GitHub release (docs/RELEASE.md). n = sideload build on this version.
android-sideload n:
    #!/usr/bin/env bash
    set -euo pipefail
    set -a; source .local/android/press-release.env; set +a
    export ANDROID_KEYSTORE_FILE="$PWD/.local/android/press-release.jks" ANDROID_KEYSTORE_PASSWORD="$STORE_PASSWORD" \
      ANDROID_KEY_ALIAS="$KEY_ALIAS" ANDROID_KEY_PASSWORD="$KEY_PASSWORD"
    export SENTRY_DSN_ANDROID="${SENTRY_DSN_ANDROID:-$(sed -n 's/^SENTRY_DSN_ANDROID=//p' .local/reliability.properties)}"
    [[ -n "$SENTRY_DSN_ANDROID" ]] || { echo "SENTRY_DSN_ANDROID is unset" >&2; exit 1; }
    version="$(sed -n 's/^openinstacine.versionName=//p' Apps/Android/gradle.properties)"
    (cd Apps/Android && JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}" ./gradlew assembleRelease)
    mkdir -p .local/apk
    cp Apps/Android/app/build/outputs/apk/release/app-release.apk ".local/apk/OpenInstaCine-$version-{{n}}-sideload.apk"
    echo ".local/apk/OpenInstaCine-$version-{{n}}-sideload.apk"

android-play-dispatch track="alpha" status="completed":
    gh workflow run android-play.yml --repo erik-sutton95/OpenInstaCine --ref main --field track={{track}} --field status={{status}}

# Owner only: write the play-closed environment secrets from .local/ (names match android-play.yml).
android-play-sync-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    set -a; source .local/play-signing.env; set +a
    repo=erik-sutton95/OpenInstaCine env=play-closed
    base64 < "$ANDROID_KEYSTORE_FILE" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$repo" --env "$env"
    gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$repo" --env "$env" --body "$ANDROID_KEYSTORE_PASSWORD"
    gh secret set ANDROID_KEY_ALIAS --repo "$repo" --env "$env" --body "$ANDROID_KEY_ALIAS"
    gh secret set ANDROID_KEY_PASSWORD --repo "$repo" --env "$env" --body "${ANDROID_KEY_PASSWORD:-$ANDROID_KEYSTORE_PASSWORD}"
    if [[ -f .local/play-service-account.json ]]; then
        gh secret set PLAY_SERVICE_ACCOUNT_JSON --repo "$repo" --env "$env" < .local/play-service-account.json
    fi
    dsn="$(sed -n 's/^SENTRY_DSN_ANDROID=//p' .local/reliability.properties)"
    [[ -z "$dsn" ]] || gh secret set SENTRY_DSN_ANDROID --repo "$repo" --env "$env" --body "$dsn"
