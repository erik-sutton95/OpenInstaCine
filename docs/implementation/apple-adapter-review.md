# Apple adapter and shared facade review

Date: 2026-09-11. Scope: read-only review of `Adapters/Insta360Apple` plus the
shared `CameraSession` / `CameraMedia` facade, against the verified Python lab,
the portable Swift protocol and the shared-engine boundary. Related decoder
issues were reported to its owner. No physical phone or camera was operated.

This review distinguishes code correctness from hardware proof: the native
adapter has not been independently re-verified on a live camera by this review.
The available camera video used for simulator QA is an explicitly labeled local
replay; it does not establish native BLE/Wi-Fi interoperability.

## Findings sent to owners

| ID | Priority | Finding / concrete trigger | Required correction |
| --- | --- | --- | --- |
| A1 | High | `LunaCameraBackend.request` reset numeric IDs between sessions/transports, but old timeout/send-error/cancellation closures removed entries using only that ID. A canceled old request could complete or cancel a newer same-ID request. | Bind each pending entry to connection generation and a unique operation ID; check both in every completion/removal path. Ignore inactive-transport receive callbacks. |
| A2 | High | TCP/Bluetooth cancellation handlers scheduled a later global disconnect/failPending without checking which operation was canceled. Cancel old connect, begin a new one, then deliver the old cancellation task: the new connection is torn down. | Guard transport cancellation/deadline callbacks with the originating generation/operation. |
| A3 | High | `CameraSession.connect` preserved the previous health/control tasks. The old health clock could see the newly cleared frame timestamp as a long stall and begin recovery during the next handshake. An old control task's generation-guarded defer could leave a non-nil task handle blocking the next control queue. | Cancel/clear old health and control tasks/queues when connecting; capture/check generation inside health sampling. |
| A4 | High | `HevcDecoder.reset` still started its inherited simulator clip injector and forced D-Log2, even when no clip was configured. The injector could compete with the explicit replay backend. Successful late VT callbacks lacked the generation guard used by error callbacks. | Remove the inherited implicit simulator source; use the explicit replay backend only. Carry VT generation into assist-result presentation and reject stale results. |
| A5 | Medium | `LunaBluetooth.disconnect` cancels a peripheral asynchronously. Immediately reusing that same peripheral can let the old disconnect callback match the new active object and clear the new connection. | Serialize teardown before reconnect, or bind CoreBluetooth callbacks to an isolated transport lifetime. |
| A6 | Medium | Heartbeats started only after all TCP reads/auth/live-start completed; the verified client begins them immediately after greeting. Stop was attempted only after receiving the live-start ACK, omitting cleanup when start arrived but its ACK was lost. | Start two-second heartbeats after greeting; track live-start-attempted before awaiting ACK and attempt stop during cleanup. |
| A7 | Medium | Any non-approval message with a matching ID consumed a pending request, including unsolicited notifications. Approval notifications could also be cached before the current authorization request. | Only 200/500 responses consume requests. Scope approval to the active command-86 attempt and discard earlier notifications. |
| A8 | Medium | The saved-Wi-Fi shortcut treated any `192.168.42.x` interface as the selected camera. With two approved Luna bodies it could show camera A's identity while displaying camera B. | Bind the network endpoint to saved camera identity/serial, or remove the shortcut until that association is verified. |
| A9 | Medium; blocks enabling media across cameras | `mediaFiles` / `mediaAssets` survived camera switches, and list/download/delete completions did not consistently carry the originating camera ID/generation. Old opaque asset IDs could be routed to the next backend connection or persisted under the next camera's catalog. | Reset/reload per-camera presentation state; capture camera ID/generation across every media await and gate publication/deletion continuation. Luna's camera-media capability is currently disabled. |
| A10 | Low | Shared discovery/reconnect created presentation `CameraModel` values with the Insta360 TCP port and `verified = true`, placing transport assumptions in the shared facade. The encrypted device-info response was authenticated but not structurally validated. | Use a neutral presentation bridge; keep endpoint/model verification in the adapter. Parse the encrypted info body with the same strict response helper. |
| A11 | High | A BE82 response can arrive before CoreBluetooth's `didWriteValueFor` acknowledgment. Resuming a request immediately on the response allowed the next command to overwrite the single BLE write continuation while its predecessor was still awaiting acknowledgment. | Retain the validated response until both the entire write and response have completed; keep that barrier under the request's deadline/generation/operation guards. |

Owners were notified immediately, with the pending-request and source-generation
issues prioritized before simulator review. The review's final resolution state
is recorded below after changes are inspected.

## Positive checks

- CryptoKit performs P-256 point construction/ECDH and HKDF-SHA256 using the
  verified salt/info and 16-byte key. Scheme-3 AAD/nonce/tag/ciphertext layout is
  supplied by the portable codec. Key-exchange success 1 is enforced.
- AES-GCM authentication happens before message parsing. A plaintext response
  cannot satisfy an encrypted request. Session keys are discarded after BLE
  handoff/disconnect; no keys or raw credential values are logged.
- Credentials and the app's own authorization UUID use device-local Keychain
  storage. The adapter does not copy the official app's client identity.
- BLE bootstrap checks model, encryption support, owner-approval status and
  encrypted Wi-Fi fields. Saved authorized status 0 uses the proto3 default.
- The native backend exposes only live-video capability. Shared controls route
  semantic intents through capability checks, and unsupported Luna controls and
  camera-media operations do not mutate fake camera state.
- TCP data callbacks carry a connection token; canceled connection data is
  discarded. Framing is bounded and checksummed, and only subtype `0x20` is
  handed to the HEVC decoder after a live-start attempt. Coalesced start ACK and
  initial keyframe data remain usable while connection completion resumes.
- Preview Rec.709 metadata is separate from camera capture settings. The root
  owner also removed brightness-based transfer inference from the shared sample
  path, preventing a Rec.709 scene from being guessed as D-Log.

## Recommended regression coverage

1. An old same-ID request's cancel, timeout and failed-send callbacks cannot
   consume a new generation's pending entry.
2. Cancel one transport connect, immediately start another, then deliver the
   old cancellation/disconnect callbacks: only the old operation ends.
3. A matching-ID unsolicited notification leaves the outstanding request intact.
4. Lost live-start ACK still causes a stop attempt; heartbeats run during a
   delayed post-greeting authorization exchange.
5. Switch cameras while the old health loop/list operation is outstanding;
   neither can mutate the new session or its media catalog.
6. Late decoder output after reset does not present/count a new frame, and
   simulator source selection never activates an implicit D-Log2 feed.
7. Unsupported control/media capabilities result in zero backend calls.
8. Deliver a valid BLE response before the final ATT write acknowledgment. The
   request remains pending and no next command is issued until the acknowledgment.
   Failed writes, cancellation and timeout each complete it exactly once.

Portable baseline verification available to the owners remains 609 root tests
and 24 Swift protocol tests. Native simulator/fake-backend tests validate these
lifecycle changes separately; those results must not be described as hardware
BLE/TCP verification.

## Resolution state

All high/medium findings and A10 were addressed by their source owners and
reinspected in the final source state of this audit:

- A1/A2/A7/A11: requests carry generation and UUID operation leases; responses
  require 200/500, the expected encryption, and complete writes. Transport,
  greeting and approval cancellation handlers reject stale operations. Approval
  is armed only for the current command-86 attempt.
- A3/A9: a new connection cancels old health/control work and clears camera media
  presentation state. Media list/download/delete work carries the originating
  camera ID/generation across awaits; canceled downloads cannot publish cache files.
- A4: the implicit simulator feed was removed. Both assist submission and result
  presentation reject stale decoder generations. Explicit replay remains labeled.
- A5/A6: BLE reconnect waits for its previous teardown callback with a bounded
  deadline. Heartbeats begin after the TCP greeting, and cleanup attempts stop
  whenever live start was attempted, including a lost ACK.
- A8/A10: normal connections always bootstrap the selected BLE camera, then
  compare its serial with the TCP camera before starting video. Encrypted device
  information is parsed and model checked; the shared legacy presentation bridge
  no longer asserts an Insta360 port or transport verification.

The BLE bootstrap also now includes the verified client's bounded five-second
initial-notification grace. Like `tools/luna_ble.py`, it proceeds to GetOptions
if that initial notification is absent; the lab does not perform a BE81 read
fallback there.

No remaining blocker was found in the audited paths by source inspection. Two
small shared-facade cleanup observations were sent to its owner: remove a
camera-brand-specific explanatory comment, and generation-guard a successful
control completion before it clears an operator note.

This signoff is a source review, not an assertion of complete concurrency-test
coverage. The recommended transport race tests above are follow-up regression
coverage; current fake-backend tests cover capability gating and shared state.
Final simulator build/test results belong in the root verification report. Native
first-install BLE consent, encrypted Wi-Fi handoff and sustained live-camera
reconnect still need a later authorized hardware run.
