# Luna Color Recovery command candidates

Research date: **2026-09-11**. Read-only primary-source investigation; no hardware access, packet transmission or application changes. Public-source declarations below are **not yet Luna-verified Color Recovery controls**.

**Later capture result:** the [confirmed screen-toggle capture](luna-recovery-toggle-capture-2026-09-11.md) identifies the screen's own configuration RPC and correlates its I-Log LUT values with decoded video changes. That measured screen command supersedes the missing-mapping status below. It does **not** verify phone photography option 73 or make the two protocols interchangeable.

**A concrete phone-protocol candidate exists: photography option 73, read through command 10 and written through command 9. No public source found maps the detached screen's Color Recovery control to its binary RPC service/method.**

## Current local baseline

The detached screen's transport is already established locally: UDP/KCP, a CRC16-protected envelope, a ten-byte binary RPC header, and a separate H.264 media channel. The startup capture independently decoded a 556×314, 8-bit H.264 picture. The setting was operator-reported On; no controlled Off comparison was present in that take. These results supersede earlier unknown-transport notes. [Screen startup evidence](luna-screen-startup-capture-2026-09-11.md), [screen RPC layout](luna-screen-udp-control.md)

## Directly declared phone command mapping

The community-published `insta360_messages.proto`, pinned at `b78dddb9cd9bc2cf632871646c6f5af238e582d4`, declares:

| Photography option | Number | Nested value type |
| --- | ---: | --- |
| `I_LOG_SWITCH` / `i_log_switch` | 72 | Boolean |
| `COLOR_RECOVERY_SWITCH` / `color_recovery_switch` | 73 | Boolean |

The numbers occur both in `PhotographyOptionType` and as fields of `PhotographyOptions`. They are **not top-level device Options fields**. [Option enum][option-enum], [value fields][value-fields]

| Message | Phone command | Protobuf fields |
| --- | ---: | --- |
| `GetPhotographyOptions` | 10 | 1: repeated option types; 2: function mode |
| `GetPhotographyOptionsResp` | Response to 10 | 1: option types; 2: nested PhotographyOptions; 3: function mode |
| `SetPhotographyOptions` | 9 | 1: repeated option types; 2: nested PhotographyOptions; 3: function mode |
| `SetPhotographyOptionsResp` | Response to 9 | 1: repeated success types |

The declared normal-video function mode is **7**. Mode selection matters: a global-looking boolean name does not make this wrapper mode-independent. [Command enum][command-enum], [GET wrapper][get-wrapper], [SET wrapper][set-wrapper], [FunctionMode enum][schema]

These declarations describe the **phone command/protobuf namespace**. They supply neither a KCP conversation nor screen RPC routing/service/method IDs. [Schema][schema]

### Derived payload examples for offline recognition

These are protobuf-body examples calculated from the declarations and standard wire encoding, **not captured Luna requests, complete UCD2 packets, or instructions to send them**. They assume function mode 7. Repeated option types are shown unpacked; a conforming parser also accepts the packed form. [Protobuf encoding][encoding]

| Purpose | Protobuf body, hexadecimal |
| --- | --- |
| Read options 72 and 73 | `08 48 08 49 10 07` |
| Read option 73 only | `08 49 10 07` |
| Set option 73 true, explicitly encoded | `08 49 12 03 c8 04 01 18 07` |
| Set option 73 false, explicitly encoded | `08 49 12 03 c8 04 00 18 07` |

The nested tags are `c0 04` for field 72 and `c8 04` for field 73, both wire type 0. In the SET examples, `12 03` introduces a three-byte nested value. A reply to SET must be interpreted through its success-types list, not just transport receipt. None of these byte examples proves that Luna's firmware implements the field. [Value fields][value-fields], [SET response][set-wrapper], [wire encoding][encoding]

### Default-false ambiguity

The source uses proto3 without `optional` on these booleans. Ordinary generated serializers omit false scalar values, so a requested false can produce an empty nested message while the option-type mask still names 73. Packed versus unpacked repeated fields can also make otherwise equivalent messages look different. Preserve the selection mask and parse both encodings. [Proto3 field presence][presence], [encoding][encoding]

An omitted field is not independently measured Off, and a decoded default false is not proof of support. Store separately: requested types, returned types, raw nested-field presence, parsed value, mode, and device/firmware identity. A matching SET acknowledgement is necessary evidence to retain, but observed readback and behavior are still needed before claiming a working setting. This is an implementation recommendation based on protobuf's presence rules, not a claimed Luna response contract. [Field presence][presence]

## What other primary sources establish

The official Android SDK exposes `CameraCapture.iLogSwitch` as a Boolean `CameraParam`. That wrapper documents cached `getValue()`, camera-fetching `fetchValue()`, `setValue()`, supported-value queries and change listeners. It also exposes separate `colorMode` and `filterMode` parameters. The inspected parameter list contains **no Color Recovery property**, and the overview covers X/ACE/GO rather than establishing Luna support. These APIs support the distinction between capture color mode and other transforms; they do not prove that SDK `iLogSwitch` corresponds to Luna's screen option or establish its wire number. [Official parameter API][android-api], [SDK scope][android-guide]

The older Luna desktop project reports measurements on **v1.0.283** in which toggling Colour Recovery visibly changed preview, yet photography/device-option sweeps through 1–400 and additional getters/notifications revealed no corresponding change. This is negative evidence from that project and firmware, not a universal impossibility result. Its original extracted PhotographyOptions schema lacks fields 72 and 73, although its probe explicitly sweeps beyond known schema fields. Do not dismiss the measured negative result merely because those names were absent. [External Luna measurements][features], [probe implementation][probe], [older extracted schema][old-schema]

That project's calibrated Luna controls instead use `color_mode` field 35 for color modes and `gamma_mode` field 18 for creative filters. Therefore discovering a boolean named `i_log_switch` elsewhere is insufficient reason to replace Luna's measured color-mode mapping. [External calibration][calibration]

## Detached-screen RPC: available evidence and missing mapping

Our local capture maps **service 11/method 1** to namespace state queries and **service 11/method 2** to length-prefixed namespace plus JSON replacement operations. The observed replacements affect the GUI focus-page path. This makes property changes a useful capture comparison, but no observed JSON path currently names Color Recovery. Inventing `/gui/color_recovery_switch` from a protobuf name would conflate unrelated schemas. [Local property-RPC evidence](luna-screen-udp-control.md)

The earlier startup trace contains a service 2/method 1 response before video starts; the corresponding request was missing. Neither that response nor the working service 2/method 3 media envelope identifies a recovery selector. [Startup evidence](luna-screen-startup-capture-2026-09-11.md)

Targeted public-code searches for `color_recovery_switch`, `i_log_switch`, `preview_reset`, `preview_initial_angle` and the observed screen GUI class name found the phone-field declaration and existing Luna observations, but no matching screen RPC implementation. Negative search results do not exclude an undiscovered firmware setting, a different name, or a screen-local rendering switch.

## Implementation implications

1. Keep **phone option 73** as a named, mode-scoped candidate. Do not label it a verified Luna Color Recovery feature until its state tracks the physical On/Off setting and a controlled write changes the intended behavior.
2. For the new screen capture, compare complete CRC-valid requests around each operator-marked transition. Match request/reply identifiers, routing, service and method before interpreting a changed byte. Keep KCP retransmissions and missing fragments out of the application-level change count.
3. Compare incoming decoded samples across On → Off → On. If the transmitted H.264 changes, that establishes an effect upstream of our decoder; if only the screen display changes, a screen-local LUT remains possible. A repeatable command correlation alone does not settle color-pipeline placement.
4. Keep the user-facing camera recovery control separate from OpenInstaCine's display LUT. Store an unknown state until actual readback is established; avoid presenting a default-false decoder result as an authoritative toggle position.
5. Any eventual writer should alter only the verified field/path and preserve capture mode, filters and other settings. No broad option sweep, new live client, or command replay is needed to finish this source investigation.

[schema]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto
[command-enum]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto#L1060
[option-enum]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto#L1959
[value-fields]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto#L6896
[get-wrapper]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto#L5157
[set-wrapper]: https://github.com/iliakonnov/insta360-nas/blob/b78dddb9cd9bc2cf632871646c6f5af238e582d4/insta360-server/insta360_messages.proto#L7418
[encoding]: https://protobuf.dev/programming-guides/encoding/
[presence]: https://protobuf.dev/programming-guides/field_presence/
[android-api]: https://github.com/Insta360Develop/Insta360-Developer_Docs/blob/caa3700d0bf2a1b96317211f64431bcd0dfe11c0/docs/en/sdk/x-ace-go/android/camera-api.md#3-capture-control-and-parameters
[android-guide]: https://github.com/Insta360Develop/Insta360-Developer_Docs/blob/caa3700d0bf2a1b96317211f64431bcd0dfe11c0/docs/en/sdk/x-ace-go/android/guide.md
[features]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/docs/FEATURES.md
[probe]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/scripts/probe-colorspace.mjs
[old-schema]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/scripts/luna-protocol-schema.json
[calibration]: https://github.com/Ripwords/insta360-luna-ultra-desktop/blob/426d643d302d6818a7d536b815ee15f73bb9c29d/docs/superpowers/specs/2026-07-25-camera-protocol-calibration.md
