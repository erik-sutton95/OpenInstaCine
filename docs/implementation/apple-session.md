# Shared Apple session and Insta360 adapter (superseded)

This file described the pre-rebase `Shared/Apple/MonitorUI` session facade,
which no longer exists. The app is now app-owned code under `ios/OpenInstaCine` on
the shared OpenCine shell (`OpenCineAppKit`), no longer synced from OpenPocketCine,
with the Luna backend wired in directly:

- Session and controls: `ios/OpenInstaCine/CameraSession.swift`,
  `CameraSessionControls.swift`, `CameraMedia.swift` (Luna extension),
  `LunaShellMapping.swift`.
- Native transport (BLE pairing, handshake, Keychain, Wi-Fi join, TCP):
  OpenCine `Sources/Insta360Apple`.
- Wire codec: OpenCine `Sources/Insta360Protocol`, described in
  [luna-swift-protocol.md](luna-swift-protocol.md).

Status: [luna-ios-status.md](luna-ios-status.md). The old text is in git
history (`git show 9deb107^:docs/implementation/apple-session.md`).
