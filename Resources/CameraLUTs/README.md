# Luna camera display conversions

`luts/Luna_I-Log_to_Rec709_BT1886_s33_v2.cube` is the **unchanged Insta360 rendering LUT**, version 2.0 (2026-05-20), supplied by the user on 2026-09-11. Its copyright remains with its provider; it is not an app-authored or Apache-licensed transform. No separate license accompanied the supplied folder.

This is the canonical asset for both applications. The thin Apple app includes it through `Apps/Apple/project.yml`; the thin Android app merges this directory as assets. Shared monitor code receives a catalog descriptor and applies generic CUBE sampling. Manufacturer filenames and catalog choices do not belong in the connection protocol.

The Camera picker offers **I-Log → Rec.709** as an explicit SDR look. It expects normalized I-Log RGB input with BT.2020 primaries. Its output is the provider's Rec.709 / BT.1886 rendering, including its tone and gamut rendering. Do not replace it with the analytical inverse transfer function. The 33-point version fits both native pipelines without the 65-to-64 resampling required by Core Image's cube dimension limit.

`manifest.json` records the hashes, sizes, and headers of all six supplied files. The 65-point SDR cube and both resolutions of the HDR cubes remain reference inputs in the user's Downloads folder; they are not bundled. The HLG and PQ cubes target Rec.2020, 1000 nits peak, and 203 nits diffuse white. Exposing those as display looks requires explicit HDR output/color management; the current SDR monitor does not provide it.

**Source metadata stays independent.** Choosing this look does not declare that the connected preview is I-Log, change capture settings, or add a camera command. Exposure compensation before this cube uses I-Log math. Source scopes retain the actual preview transfer. Current Luna preview metadata remains Rec.709, so Auto stays neutral. An I-Log recording setting alone is insufficient to change that behavior.

The curve, gamut, rounding details, source PDF hash, and independent numerical fixtures are in [`docs/research/luna-i-log-white-paper.md`](../../docs/research/luna-i-log-white-paper.md). Luna Pro transport and metadata identification still require evidence; this color profile does not establish connection compatibility.
