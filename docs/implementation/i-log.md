# I-Log color support

Implemented 2026-09-11 from the supplied Insta360 white paper and Luna LUT folder. Exact equations, gamut, source hashes, and numerical reference samples are in the [research note](../research/luna-i-log-white-paper.md).

## Available now

- Both native Camera LUT pickers offer **Auto** and **I-Log → Rec.709**, alongside the inherited Creative and Custom categories.
- The official v2 33-point SDR rendering cube is stored once in `Resources/CameraLUTs/luts` and bundled by the thin brand apps. The six-source manifest also records the 65-point SDR and 33/65-point HLG/PQ alternatives, without shipping unused HDR transforms.
- `MonitorCore.CameraLUT` describes a stable ID, title, resource filename, and input transfer. The compatibility LUT choice preserves existing raw-string/JSON preferences and adds `camera:<id>` choices. Apple brand configuration and Android monitor configuration inject their catalogs.
- `MonitorTransfer.ilog` implements the paper's curve and BT.2020 luminance. The Android rendering bridge uses the explicit monitor identifier `65536`, outside the legacy camera-byte range. No I-Log value was inserted into DJI's wire `ColorMode`.
- Manual conversion uses I-Log for pre-LUT exposure compensation; Apple export baking uses the same input domain. Source scopes, false color, and zebra keep the actual source metadata. I-Log Stops analysis decodes RGB before computing linear BT.2020 luminance. DJI preview/EI calibration does not apply to I-Log.
- Apple image effects and preview metadata now carry a neutral transfer independently of recording settings. An explicit future I-Log preview can select its automatic camera look. Current Luna backend metadata remains Rec.709. Android Auto remains neutral until its backend snapshot gains authoritative preview-transfer metadata; manual conversion is supported now.

## Boundaries

An I-Log recording setting does not prove that the network preview is I-Log. The supplied paper does not define BLE commands, preview flags, clip metadata keys, or transport range normalization. The verified Luna recording of the live preview is 8-bit Rec.709; it is not an I-Log test chart. Brightness-based transfer guessing is absent from live and playback paths.

The paper's normalized 10-bit examples are curve values, not a rule to apply video-range offsets. Full/limited YUV handling remains in decoder/sampling code. Real 10-bit I-Log camera recordings are still needed to validate container metadata and end-to-end range interpretation.

HLG/PQ LUTs specify 1000-nit output and 203-nit diffuse white. They require explicit HDR display/output management and are not offered as SDR looks. Neither this shared profile nor the user's identification of Luna Pro establishes Pro transport compatibility.

## Validation

- Portable shared/compatibility/JNI: **624 tests in 56 suites**, including published anchors, rounded branch boundaries, round trips, BT.2020 colored pixels, official LUT samples, catalog persistence, and exact RGBA8 exposure fixtures.
- Apple: **423 tests**, one optional existing movie fixture skipped, zero failures. New integration tests load the actual app-bundled cube, preserve source metadata, exercise exposure/export/persistence, and validate I-Log source publication and scope rendering.
- Android: **479 JVM tests**, app/monitor/Luna lint, and debug APK pass. The APK's sole CUBE is byte-identical to the canonical supplied s33 file; the packaged native library was rebuilt after the final I-Log math change.

All device execution in this change is simulator-only. No connected physical phone was installed, launched, or operated.
