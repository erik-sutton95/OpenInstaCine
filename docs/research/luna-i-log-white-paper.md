# Luna I-Log: supplied specification and rendering LUTs

Reviewed 2026-09-11. This note separates statements in the supplied materials from calculations and transport questions that still need camera evidence. The PDF's printed page numbers omit its cover and contents: printed pages 1-4 are physical PDF pages 3-6. The equations and gamut table were checked against rendered physical pages 5 and 6, not just extracted text.

## Source provenance

- User-supplied PDF: `/Users/eriksutton/Downloads/Insta360_10-bit_I-Log_White_Paper.pdf`, 1,039,732 bytes, SHA-256 `20bc91f90a56b14dceae32c0d425b5d344d38aa68875a5b14b81d612b082a81d`. Cover: June 2026. Revision history: final pre-release bug fix dated 2026-05-20 (printed p1 / physical p3).
- User-supplied folder: `/Users/eriksutton/Downloads/Luna_Series_I-Log_LUTs`. All six CUBE headers identify version 2.0 and creation date 2026-05-20. No separate documentation or license file was present in that folder. These hashes identify the exact local inputs; their original download URLs were not supplied.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `Luna_I-Log_to_Rec709_BT1886_s33_v2.cube` | 1,401,671 | `e3e5c3ab4ca7c166f3ebb740b45ed8cbce649b0c18dca9d5661754c53b9ee17d` |
| `Luna_I-Log_to_Rec709_BT1886_s65_v2.cube` | 10,710,503 | `06db0a02784fed3a5db4ef7fb3ee617c63c3b45b699653108927fa3917578d80` |
| `Luna_I-Log_to_Rec2020_HLG_1K_DW203_s33_v2.cube` | 1,401,703 | `312332772b49774138967dcb7648921a0fa6bce78ef259d2788942a47dbe13fc` |
| `Luna_I-Log_to_Rec2020_HLG_1K_DW203_s65_v2.cube` | 10,710,535 | `c1a70fe2977df8c9d52f913188a6d8edfc4b0befdef869e957589deefbb97fc5` |
| `Luna_I-Log_to_Rec2020_St2084_1K_DW203_s33_v2.cube` | 1,401,705 | `4243713458a72e351c8dff1ff626ba0d64b817d69d7fa542a1d43363c2860616` |
| `Luna_I-Log_to_Rec2020_St2084_1K_DW203_s65_v2.cube` | 10,710,537 | `b3bb1e772817bc4b66b737220923824a6f8f51d38aa1bb0f04aa869a0e20dfdb` |

## Exact transfer function

The PDF describes a scene-referred curve (printed p2 / physical p4). Scene reflectance is a ratio: 18% is `0.18`, 100% is `1`, and 2200% is `22`. It is not absolute display luminance.

Using the published constants without fitting or changing the branch inequalities (printed p3 / physical p5):

```text
alpha = 5.77837328
beta  = 0.09055934
delta = 0.623992
eta   = 0.280055
theta = 0.01

encode(x):
    if x <= 0.01104854: alpha * x + beta
    otherwise:         delta + eta * log10(x + theta)

decode(y):
    if y < 0.154402: (y - beta) / alpha
    otherwise:      10^((y - delta) / eta) - theta
```

The table in the paper gives black `0.0905593 / 93`, 18% gray `0.422003 / 432`, and 2200% `1.0 / 1023` as floating-point / 10-bit pairs. Evaluation of the more precise published coefficients gives:

| Scene reflectance | Encoded float | Float times 1023 | Nearest 10-bit code |
| --- | ---: | ---: | ---: |
| 0% | 0.0905593400 | 92.64220482 | 93 |
| 18% | 0.4220033397 | 431.70941653 | 432 |
| 100% | 0.6252022223 | 639.58187345 | 640 |
| 2200% | 0.9999994560 | 1022.99944351 | 1023 |

Derived numerical details useful for tests:

- At the forward breakpoint, the linear branch produces `0.15440192831901123`; the logarithmic expression produces `0.15440193077978148`. The gap is approximately `2.46e-9` in encoded units.
- At the inverse breakpoint, the two expressions differ by approximately `4.26e-10` in scene reflectance. The inverse threshold itself is rounded to six decimal places. Exact bitwise round trips at this boundary are not promised by these published decimal coefficients.
- `decode(1)` is approximately `22.00009844`, rather than exactly `22`; this agrees with the rounded 2200% table anchor. `decode(432/1023)` is approximately `0.18044425`, rather than exactly `0.18`, because the code value is quantized.
- The formulas themselves do not prescribe clipping. `decode(0)` is approximately `-0.01567212`, and scene values above `22` encode above `1`. Keep any display, histogram-bin, or user-input clamp separate from the mathematical definition.

The paper's paired anchors support **normalized code = code / 1023**, not substituting a `64...940` normalization into these equations. That does **not** establish how a particular recorded HEVC file or live preview packs RGB/Y'CbCr, whether its video-range flag is correct, or whether a decoder has already expanded legal range. Transport/decoder range conversion must be verified separately and applied exactly once before interpreting the curve.

`MonitorCore` implements the exact expressions internally as the appended `MonitorTransfer.ilog` case. Its existing public monitoring API retains its established clamps: encoded input/output stay in `0...1`, and negative decoded reflectance becomes zero. I-Log scope anchors use the paper black and middle gray. Until 2026-10-20 encoded `1` was the 100-line ceiling at every ISO, so clipping below ISO 400 went unflagged. The ceiling now follows ISO through OpenCine `LunaScopeClip` (see the implementation note). The Android rendering bridge uses the neutral identifier `65536`, outside its compatibility camera-byte range. This identifier is not a camera wire enum.

## Gamut and exposure calculations

The PDF explicitly assigns BT.2020 RGB primaries and white point (printed p4 / physical p6): red `(0.708, 0.292)`, green `(0.170, 0.797)`, blue `(0.131, 0.046)`, and white `(0.3127, 0.329)`.

Solving those chromaticities for a white with `Y = 1` gives this **derived**, scene-linear RGB-to-XYZ matrix:

```text
[X]   [0.6369580483  0.1446169036  0.1688809752] [R]
[Y] = [0.2627002120  0.6779980715  0.0593017165] [G]
[Z]   [0.0000000000  0.0280726930  1.0609850577] [B]
```

Thus scene-linear luminance uses approximately `0.2627 R + 0.6780 G + 0.0593 B`. For exposure analysis of RGB I-Log, first decode each channel and then combine linear channels. Applying the inverse curve to a weighted sum of encoded channels is generally different for colored pixels. A BT.709-weighted helper should not silently become the exposure model for a BT.2020 input. Stops relative to middle gray are `log2(Y / 0.18)` for positive scene luminance; handling zero and negative values belongs to the consuming assist's policy.

BT.2020 primaries do not by themselves imply HDR output, a particular HLG/PQ transfer, a particular Y'CbCr matrix or bit depth, or any measured sensor dynamic range. The curve's representable highlight headroom is not a sensor-performance measurement.

## What the supplied LUTs do

The headers call these **rendering LUTs**, with three explicitly different outputs:

| Output family | Header specification | Grid choices |
| --- | --- | --- |
| SDR | Rec.709 / BT.1886 | 33 and 65 |
| HLG | Rec.2020 / HLG / 1000 nits / 203 nits diffuse white | 33 and 65 |
| PQ | Rec.2020 / ST 2084 / 1000 nits / 203 nits diffuse white | 33 and 65 |

The SDR s33 file has exactly `33^3 = 35,937` RGB entries, all finite, spanning `0...1`, and no explicit `DOMAIN_MIN` or `DOMAIN_MAX` declaration. The following independent samples use a unit input domain, red-fastest CUBE ordering, and trilinear interpolation over all eight surrounding vertices. Input channels are equal and come directly from the published forward curve. These are reproducible measurements of the supplied file, not additional claims made in the paper.

| Scene input | Encoded input R=G=B | SDR LUT output R, G, B |
| --- | ---: | --- |
| Black (0%) | 0.0905593400 | 0.00438712, 0.00437246, 0.00425046 |
| Middle gray (18%) | 0.4220033397 | 0.38463754, 0.38836461, 0.38811411 |
| 100% | 0.6252022223 | 0.75309980, 0.75316732, 0.75308445 |
| 200% | 0.7089035719 | 0.85980107, 0.86117940, 0.86060947 |
| 400% | 0.7929055973 | 0.93776587, 0.93834284, 0.93733674 |
| 800% | 0.8770588043 | 0.97938316, 0.97937047, 0.97921710 |
| 1600% | 0.9612878145 | 0.99448042, 0.99441755, 0.99440552 |
| 2200% | 0.9999994560 | 0.99942007, 0.99942008, 0.99942008 |

The exact LUT origin at encoded `(0,0,0)` is `(0.0005035477, 0.0013122759, 0.0011749447)`; the exact `(1,1,1)` node is `(0.9994201572, 0.9994201572, 0.9994201572)`. Neither node is the analytical scene-black anchor. Small channel differences and a raised interpolated black should not be “corrected” by replacing this supplied rendering transform with an idealized one-dimensional curve. Tetrahedral interpolation and the s65 grid can produce different intermediate results.

The SDR samples demonstrate highlight compression: scene-linear `1` renders near `0.753`, with substantial room still reserved for highlights. This LUT is not merely the inverse I-Log function followed by clipping, nor is its output an appropriate replacement for scene-linear values in exposure analysis. Apply the supplied transform to encoded I-Log RGB; do not decode I-Log first and then feed scene-linear values into an I-Log-input LUT.

## What these materials do not establish

- The paper does not enumerate supported camera models, firmware revisions, or recording modes. The filenames identify the Luna family; the user's note identifies Luna Ultra and Luna Pro. Model-specific capability negotiation still needs device evidence.
- No BLE command, recording-profile enum, preview-status field, or connection-handshake change is specified here.
- No evidence here proves that choosing I-Log for recording also makes the live preview I-Log. Existing verified Rec.709 preview behavior must remain separate from recording metadata until that relationship is measured.
- Neither the paper nor these headers describe live-preview bit depth, chroma subsampling, full versus legal transport range, or how to identify the transfer after VideoToolbox/MediaCodec decoding.
- The HDR LUT headers give output targets, but do not provide display negotiation, EDR/HDR surface configuration, color-space attachments, HLG system-gamma handling, or output metadata policy. Applying an HLG/PQ LUT to an ordinary SDR surface does not implement an HDR monitor.

Implementation can safely add the exact curve, BT.2020 identity, verified numerical fixtures, and explicit SDR I-Log rendering support. Automatic selection should require an authoritative preview signal or an explicit user override, rather than brightness heuristics or recording-mode inference. HDR display integration and wire capability mapping remain separately verifiable work.
