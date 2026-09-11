# Shared Apple session and Insta360 adapter

The inherited monitor screens depend on one presentation facade in `Shared/Apple/MonitorUI/CameraSession.swift`. That facade owns hardware decoding, measured presented-frame rate, warmup, bounded recovery, interface lock, local media cache, and UI notes. It no longer constructs a DJI BLE link, datalink driver, DUML request, or Osmo live-enable command.

`Sources/MonitorContracts` is Foundation-only. `CameraBackend` supplies discovery, connection phases, camera information/status, Annex-B access units, camera capabilities, semantic control intents, media operations and network handoff. Native backend types and wire message types do not appear in its API. Capture telemetry is separate from preview dimensions/rate; missing capture metadata remains unknown.

Control values cross the boundary as units (ISO number, shutter seconds, exposure stops, zoom ratio, normalized focus/tracking coordinates) or semantic option names. The facade checks capability, established connection and interface lock before dispatch. Writes run serially with a bounded queue; pending gimbal and zoom intents coalesce. Camera status changes only on a backend status event. Luna currently advertises **live video only**: camera controls, media catalog/transfer, audio and gimbal operations cannot reach its wire layer.

The media extension preserves local cache, thumbnails, catalog, favorites, shot-color metadata and offline playback. Future backend media listings project into the inherited library model, while original opaque asset IDs remain in a separate persistent catalog. The temporary legacy UI handle only controls delete affordance and is never sent to an adapter. Downloads use a temporary file, validate the original size when known, and move to the cache only after successful completion. Opening or closing the library does not stop the live video transport.

## Luna native implementation

`Adapters/Insta360Apple` implements CoreBluetooth, CryptoKit, Keychain, hotspot association and Network.framework. Its portable framing/parsing dependency is `Adapters/Insta360Protocol`.

1. Find BE80 advertisements and open BE81 writes / BE82 notifications.
2. Check the exact observed camera model; negotiate scheme 3 using ephemeral P-256 ECDH, HKDF-SHA256 and AES-128-GCM.
3. Use a persistent **own** installation identity from Keychain. An unapproved installation waits for explicit approval on the camera. Wi-Fi credentials are decrypted and stored in Keychain, never in UserDefaults or logs.
4. Join the camera's access point on a physical iOS device. On Mac Catalyst, network association is supplied by macOS Wi-Fi settings; the adapter does not execute privileged shell operations.
5. Bind TCP to the local camera-subnet address, send the verified preface, validate model and authorization, query capture state and start the verified live profile. Keepalive type 5 runs every two seconds.
6. Parse bounded, checksummed UCD2 frames; only subtype 0x20 becomes HEVC Annex-B access units. Other media subtypes remain uninterpreted. Disconnect sends the verified stop command when a start was attempted, including a lost start acknowledgement, and releases sockets, continuations, heartbeat tasks and key material.

The app's DEBUG entrypoint may inject an already approved project identity and use an already associated camera network for Simulator/Mac testing. No identity or password is compiled into the app. The release initializer follows BLE owner consent.

The observed Luna fixture contains 10 VPS/SPS/PPS/IDR groups over 467 frames (roughly a two-second keyframe interval). Decoder ownership changes therefore wait for the camera's next keyframe. Shared assist toggles never emit an unverified camera restart command.

## Lifetime and handoff invariants

- Constructing a SwiftUI state candidate does not bind the backend. The retained session binds only when activated, so a discarded initializer cannot steal live frame events.
- Request IDs are scoped by connection generation and a unique operation lease. Late cancellation, failed writes, timeouts and old BLE notifications cannot complete or cancel a newer request with the same ID.
- A request completes only after both the validated response and the transport write acknowledgement. CoreBluetooth notifications may arrive before the ATT write callback; the next command must wait for both.
- BLE reconnect waits for the previous peripheral teardown callback before reusing that peripheral. Power, connection and write waiters have separate operation identities.
- The Wi-Fi handoff compares camera serial identity with the selected BLE device without exposing it in logs. Sharing a camera subnet does not prove the selected camera is connected.
- Approval notifications are accepted only during the active authorization request. Authenticated device information is parsed and checked. Initial BLE notification grace and TCP greeting waits are bounded.
- Connect/disconnect invalidate prior health checks, control queues and media work. Catalog, progress and delete results are checked against both camera and generation before publishing. Intentional internet handoff suspends recovery until rejoin.

## Verification and limits

The portable UCD2 package has its own fixture tests. `CameraBackendFacadeTests` verifies unsupported commands never reach the adapter, enabled controls use semantic intents without optimistic camera telemetry, exposure units, interface lock, media overlay transport continuity, separation between preview and capture metadata, discarded SwiftUI state ownership, and stale catalog isolation across camera switches.

An independent source review of correlation, cancellation, encryption, camera handoff and media lifetime found no remaining blockers after the corrections above. The first complete iOS Simulator app build succeeded; the root task records final native/UI suite and runtime results after integration.

The existing phone is explicitly out of scope for automated launches because the owner is running another process on it. Physical first-install Bluetooth consent and iOS hotspot association require later on-device verification. Simulator replay validates shared decode, rendering and UI against recorded camera packets, not a new hardware connection. Record final build/runtime evidence separately in the root implementation report.


## Unavailable controls and retained shell

Capture panels retain the inherited layout and option lists. Each sheet declares the backend capability it requires; unavailable sheets show an explanation, disable camera writes, and omit a selected value instead of seeding plausible camera defaults. The Focus tile stays visible. Shutter Speed / Angle remains a local display preference, but neither unit mode invents an unknown shutter value; angle also requires actual capture frame-rate telemetry.

The AUDIO tool stays visible with an unavailable explanation when `.liveAudio` is absent. Previously saved audio-overlay preferences render an N/A placeholder, and VoiceOver reports unavailable audio instead of claiming silent channels. Playback audio retains its independent decoded source.

Link settings use connection phase, the actual camera-network state, recovery/held-picture state, and an optional source label. Local replay is labeled as such; held pictures and recovery never claim an active camera link. Luna Wi-Fi preview does not claim Bluetooth remains connected after bootstrap, and the link tile does not manufacture signal bars from decoder initialization.

`deleteMediaFiles` returns `true` only after every requested deletion succeeds for the current camera and session generation. Unsupported, empty, stale, cancelled, missing, read-only, or failed selections return `false`; failed assets remain in the catalog. Confirmed items are persisted individually if a later item fails. The player and selection UI use the result before navigating away.

Facade regressions cover capability mappings, unknown shutter units, unavailable audio accessibility, replay/held/active transport labels, failed deletion preserving the catalog, and read-only deletion avoiding the adapter.
