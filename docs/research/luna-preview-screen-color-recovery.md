# Luna Ultra: camera screen coexistence and pre-LUT preview

Research date: **2026-09-11**. Scope: current official Insta360 manuals, support pages, and published SDK documentation. This research performed no camera operations. Local measurements and external protocol-code findings should be recorded separately below or linked from this note.

The requested outcome is simultaneous camera-screen monitoring and an independent **pre-LUT I-Log preview stream while the camera's Color Recovery remains enabled**. “Raw” here means unconverted I-Log image values, not sensor RAW.

## Findings

| Question | Official evidence | What remains open |
| --- | --- | --- |
| Can the camera keep its own preview while the app is shooting? | Luna's phone-connection manual explicitly documents that the camera cannot show synchronized preview during app shooting. [Phone connection][phone] | Whether an alternative client/session state can avoid this behavior on v1.0.288. The manual does not document an override. |
| Does detaching the screen solve it? | The screen supports standalone wireless preview; the phone can connect with it detached. [Remote][remote], [phone FAQ 8][phone] | Neither statement promises simultaneous phone and remote preview. No documented exception to the app-preview limitation was found. |
| Is an independent pre-LUT I-Log stream documented? | No Luna-specific stream selector or separate Color Recovery routing control was found in the official sources checked. | This is **unknown**, not proof that a separate internal stream cannot exist. |
| Can USB/UVC or HDMI supply an alternative? | Luna's PC FAQ says webcam use and USB-C-to-HDMI output/HDMI input are currently unsupported. Wired phone connection is for file transfer only. [PC FAQ][pc], [phone connection][phone] | These are documented product limitations; no supported wired live-monitoring alternative was found. |

## Screen behavior and a limited SDK lead

The official phone guide says:

> “When you connect the camera to the Insta360 app for shooting, it is unable to synchronize the preview through the camera.”

It also prohibits simultaneous connections to two phones or to a phone and computer, and allows connecting the app with the touchscreen detached while recommending attachment for smoother connection. These are distinct restrictions and capabilities; none establishes two concurrent preview displays. [Phone connection][phone]

The detachable remote guide describes independent wireless viewing and controls, with a nominal 20 m range. It discusses microphone coexistence but provides no app-and-screen preview mode. Therefore detachment is a worthwhile observation to record, but is not an officially documented workaround. [Detachable Touchscreen Remote][remote]

There is a relevant **other-model** SDK clue. The official iOS API's Camera Lock Screen section documents `setAppAccessFileState(.liveView)` and `.idle`, with numeric enum values 5 and 1. Its initial scope is X4/X5. The X6 subsection says the same command behaves differently depending on whether a live stream is already running: without one it exits low-power mode; with one it locks the screen. This supports examining the separation between app-access state and stream startup in our capture. It does **not** establish that changing this state preserves Luna's camera preview. [Pinned iOS API, Camera Lock Screen][ios-api]

## Color Recovery: official documentation conflicts with the device report

The current English and Chinese Luna I-Log FAQs still deny in-camera restored-color monitoring; the English answer begins “No, this is not currently supported.” This conflicts with the user's reported Color Recovery behavior on the newer camera firmware. Treat this portion of the manual as outdated or incomplete for the observed firmware, rather than treating it as a reason to reject the observation. No current official firmware-release note resolving the discrepancy was located in this research. [English I-Log FAQ 6][ilog], [Chinese I-Log FAQ 6][ilog-zh]

The same manual distinguishes creative filters from original I-Log footage: applied filters are embedded in recorded media, and retaining original flat I-Log requires no filter. This does not establish how the newer Color Recovery monitor setting affects the encoded Wi-Fi preview, nor whether it affects recordings. [I-Log FAQ 5][ilog]

Insta360's app LUT instructions describe applying the official LUT to selected existing media in editing/album workflows. That is a separate post-production operation and provides no evidence for a live pre-LUT stream selector. [Official app LUT instructions][app-lut]

Do not infer the stream's image encoding solely from its color metadata. The Luna I-Log FAQ says recorded Log media can carry BT.709 metadata even though its intended input gamut is Rec.2020. That warning concerns recorded media; it does not positively identify the preview either. A metadata tag alone cannot settle our preview question. [I-Log FAQ 11][ilog]

The official June 2026 white paper specifies I-Log's scene-referred transfer function and BT.2020 primaries. Its reference mapping places 18% reflectance at normalized 0.422003, or 10-bit code 432. This offers a color-validation reference once exposure, decoder range normalization, white balance, and patch values are controlled. It supplies no network command or preview-routing information. [10-bit I-Log White Paper, pages 2–4][whitepaper]

## Official SDK preview controls do not establish a Luna bypass

The official documentation repository's current HEAD was checked on 2026-09-11: commit `caa3700d0bf2a1b96317211f64431bcd0dfe11c0`, dated 2026-09-08. Android V2 documents X/ACE/GO; iOS and desktop list X/ONE models without Luna. Desktop camera control is described as USB-only. Luna support is therefore unconfirmed in these public guides. [Android overview][android-guide], [iOS overview][ios-guide], [desktop overview][desktop-guide]

Android V2's `CameraPreview` exposes start/stop, key-frame requests, preview parameters, bitrate, decoder configuration, and frame callbacks. Its video frame categories are regular, left-side and right-side frames; they are not described as before/after Color Recovery outputs. The documented RTMP parameters cover URL, dimensions, frame rate, bitrate and network. No Luna-specific pre-LUT or independent monitor-LUT selector appears in this section. In particular, `setStreamEncode(isH265)` is described as a decoder override, not a camera color-pipeline choice. [Pinned Android Camera API, Live Preview][android-api]

## Local handshake and media audit

The current `LunaProtocol.startLiveRequest` body is `10012080f702382b500e6001`: varint fields **2=1, 4=48000, 7=43, 10=14, 12=1**. Our native Apple client performs the verified BLE consent/credential exchange, disconnects BLE, then sends the TCP preface, information query (8), authorization check (39, initiator 1), capture-state query (15), and live start (1), followed by heartbeats and live stop (2). It sends no screen-off, app-access-state, or camera-settings write. Consequently, the observed screen behavior is not caused by an explicit screen-off command implemented in this client. Which session transition causes it is still unmeasured.

All media subtypes were re-examined in the previously recorded firmware **v1.0.288** session `captures/20260910T231730790212Z-luna-tcp`. The Color Recovery switch state was not recorded in that session. This audit establishes what arrived under that captured start profile; it does not establish the topology for every possible profile or the latest switch state.

| Subtype | Observed payloads after the nine-byte media header | Interpretation |
| --- | --- | --- |
| `0x20` | 467 packets, 12,604,168 bytes, valid Annex-B HEVC; previously decoded at 1280×720 / 25 fps | The one confirmed image stream |
| `0x30` | 187 packets, each 5,600 or 5,544 bytes; all exact multiples of 56. Records parse as a little-endian UInt64 and six doubles; initial timestamp increments are 1, and channels have acceleration/rotation-like values | Structured motion-sensor records are strongly indicated; this is not evidence of a secondary compressed picture |
| `0x40` | 467 packets of exactly eight bytes each; the initial values decode as Double `0.0299902` | A per-frame scalar consistent with exposure duration, **an inference**, not another image stream |

The audit summary and privately extracted channels are under `.local/luna-stream-audit/`. Some public receiver comments label `0x30` as secondary preview and `0x40` as gyro. Those labels conflict with the structure measured here and must not be used as Luna routing facts. [Community receiver][community-receiver]

## External protocol leads, with limits

The reverse-engineered schema declares primary bitrate/resolution fields **6/7**, secondary **9/10**, and `previewStreamNum` **11** in `StartLiveStream`. Field **12** is named `enableRotate`. Field **14** selects transport (USB/Wi-Fi/Bluetooth); its name `source` does not refer to a sensor or ISP processing stage. The current request already contains a secondary-resolution field but omits stream count. Neither a field name nor a default proves whether Luna will emit two streams, or whether either branches before Color Recovery. No declared field in this message explicitly selects a pre-LUT image. [Pinned schema][community-schema]

Photography options **72/73** are named `i_log_switch` and `color_recovery_switch`, but Luna-specific measurements report that toggling Color Recovery on firmware v1.0.283 changed the picture without changing responses in their broad option/notification comparison. A descriptive field name, an echoed option ID, or a default false value is therefore insufficient to map the real Luna switch. This negative result concerns that investigation and firmware; it does not prove that no accessible switch or independent image path exists. [Measured feature report][community-features]

The practical next experiment is to compare evidence-backed preview profiles while keeping Color Recovery enabled, inventory all received channels, and independently decode any second video channel. Two encodings of the same already-converted image would not satisfy the requested pre-LUT path. A temporary recovery-off reference can help classify the result, but is not the requested workaround.

## Capture recommendations

These are proposed evidence-gathering steps, not completed measurements or promised workarounds:

1. **Keep the requested outcome fixed:** Color Recovery remains on while testing candidate independent stream profiles. A temporary off/on reference capture may help classify image values, but turning it off is not the requested solution.
2. Record whether the camera screen stops at authentication, an app-access-state command, or live-stream startup. Record attachment state and whether a still-visible screen actually continues updating. Compare the official app with our minimal client while changing one session action at a time.
3. Inspect the camera-advertised configuration and observed stream-start fields for actual stream/profile selectors. Preserve full request/response bytes and media channel identifiers. Multiple resolutions or left/right channels alone do not prove pre-LUT routing.
4. Use a fixed, manually exposed scene with neutral and colored patches. Compare decoded incoming frames before any app-side processing. A successful pre-LUT claim needs image evidence as well as a successful command response. Where useful, compare against original I-Log recordings and the official transfer function, accounting for video-range scaling.
5. Keep “camera capture color mode,” “incoming preview transform,” and “app display LUT” distinct in the shared monitor engine. A client-side LUT toggle only controls our rendering. If the received pixels already contain a camera transform, disabling our LUT does not retrieve the original pre-transform samples.

Until those observations establish a separate route, the accurate capability status is: **camera-screen coexistence is restricted by the documented app behavior; independent pre-LUT I-Log with Color Recovery enabled is unverified.**

[phone]: https://onlinemanual.insta360.com/lunaultra/en-us/operation-tutorials/connection/phones-tablets
[remote]: https://onlinemanual.insta360.com/lunaultra/en-us/operation-tutorials/appearance/touchscreen-remote
[pc]: https://onlinemanual.insta360.com/lunaultra/en-us/operation-tutorials/connection/pc
[ilog]: https://onlinemanual.insta360.com/lunaultra/en-us/operation-tutorials/shooting-preview/shooting-specs/i-log
[ilog-zh]: https://onlinemanual.insta360.com/lunaultra/zh-cn/operation-tutorials/shooting-preview/shooting-specs/ilog
[app-lut]: https://onlinemanual.insta360.com/app/zh-cn/operation_tutorial/edit_function/lut
[whitepaper]: https://wassets.insta360.com/common/31f0330509384b7b8ba0a07f4ff4eb13/Insta360_10-bit_I-Log_White_Paper.pdf
[ios-api]: https://github.com/Insta360Develop/Insta360-Developer_Docs/blob/caa3700d0bf2a1b96317211f64431bcd0dfe11c0/docs/en/sdk/x-ace-go/ios/api.md#camera-lock-screen
[android-api]: https://github.com/Insta360Develop/Insta360-Developer_Docs/blob/caa3700d0bf2a1b96317211f64431bcd0dfe11c0/docs/en/sdk/x-ace-go/android/camera-api.md#4-live-preview
[android-guide]: https://github.com/Insta360Develop/Insta360-Developer_Docs/blob/caa3700d0bf2a1b96317211f64431bcd0dfe11c0/docs/en/sdk/x-ace-go/android/guide.md
[ios-guide]: https://github.com/Insta360Develop/Insta360-Developer_Docs/blob/caa3700d0bf2a1b96317211f64431bcd0dfe11c0/docs/en/sdk/x-ace-go/ios/guide.md
[desktop-guide]: https://github.com/Insta360Develop/Insta360-Developer_Docs/blob/caa3700d0bf2a1b96317211f64431bcd0dfe11c0/docs/en/sdk/x-ace-go/desktop/guide.md
[community-schema]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto
[community-receiver]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/src-tauri/src/luna.rs
[community-features]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/docs/FEATURES.md
