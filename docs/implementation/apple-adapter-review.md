# Apple adapter and shared facade review (superseded)

This file held a 2026-09-11 read-only review (findings A1 to A11) of
`Adapters/Insta360Apple` together with the pre-rebase `Shared/Apple`
`CameraSession` / `CameraMedia` facade. The facade was replaced by the
OpenPocketCine shell under `ios/OpenInstaCine` (now app-owned code on the shared
OpenCine shell, `OpenCineAppKit`, no longer synced), and the adapter has changed
since (BLE-first connect, join retry, fw 1.1.15 fixes), so the findings no
longer map onto current code. They have not been re-reviewed against it.

Current status: [luna-ios-status.md](luna-ios-status.md). Current code:
OpenCine `Sources/Insta360Apple`, `ios/OpenInstaCine/CameraSession.swift`,
`CameraSessionControls.swift`, `CameraMedia.swift`. The old review is in git
history (`git show 9deb107^:docs/implementation/apple-adapter-review.md`).
