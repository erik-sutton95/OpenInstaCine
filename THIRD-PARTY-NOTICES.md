# Third-party notices

OpenInstaCine is licensed under the [Apache License 2.0](LICENSE). It distributes the following
third-party software, reproduced here with their required license texts, and records protocol
references that are **not** distributed.

## Inherited OpenPocketCine / OpenZCine code

OpenInstaCine extracts native monitor code, resources and tests from OpenPocketCine commit
`9c4e7334ca4d935c5d467abecaf8f968f7927d84` under Apache 2.0.
Copyright 2026 Erik Sutton and OpenPocketCine contributors.
Original source comments and credits are retained. The extraction provenance is recorded in
[`docs/implementation/baseline-provenance.json`](docs/implementation/baseline-provenance.json).
The existing OpenZCine contributions, including the cube parser and Android native staging
pattern, retain their attribution.

## CubeLUT parser

- **Source:** adapted from [OpenZCine](https://github.com/erik-sutton95/OpenZCine)
- **Used for:** portable `.cube` LUT parsing in `Sources/MonitorCore/CubeLUT.swift`
- **License:** Apache License 2.0 (same as this project)

## Sora

- **Homepage:** <https://github.com/sora-xor/sora-font>
- **Used for:** shared Apple and Android UI type
- **License:** SIL Open Font License 1.1 (full text in `Shared/Apple/MonitorUI/Resources/Fonts/OFL-Sora.txt`)
- **Copyright:** 2019 The Sora Project Authors

## IBM Plex Sans

- **Homepage:** <https://github.com/IBM/plex>
- **Used for:** shared Apple and Android UI type
- **License:** SIL Open Font License 1.1 (full text in `Shared/Apple/MonitorUI/Resources/Fonts/OFL-IBMPlexSans.txt`)
- **Copyright:** 2017 IBM Corp. with Reserved Font Name "Plex"

## Protocol references (not distributed)

The inherited OpenPocketCine implementation learned its BLE pairing and camera Wi-Fi connection path from the public
[Osmosis](https://github.com/KonradIT/osmosis) project by Konrad Iturbe. This project preserves that acknowledgment. No
Osmosis source is included in or distributed with this project. OpenPocketCine developed its
live view, monitoring and native shells independently; OpenInstaCine inherits that shared shell.

No DJI SDK or proprietary DJI documentation is included in, distributed with, or required by this
project (see [NOTICE](NOTICE), the
[protocol handbook](https://openpocketcine.app/docs/), and
[`docs/protocol-notes.md`](docs/protocol-notes.md)).

## Lucide HUD icons

- **Homepage:** <https://github.com/lucide-icons/lucide>
- **Used for:** HUD and chrome glyphs on iOS and Android (`OpcIcon`). Vendored SVGs live in
  `Shared/Apple/MonitorUI/Resources/Icons/lucide/` and
  `Apps/Android/monitor/src/main/assets/icons/lucide/`; Android also ships VectorDrawables under
  `Apps/Android/monitor/src/main/res/drawable/opc_lucide_*.xml`.
- **License:** ISC (full text in those `LICENSE.txt` files). Some glyphs in this set are derived
  from [Feather](https://github.com/feathericons/feather) and are additionally MIT
  (`aperture`, `check`, `chevron-down`, `chevron-left`, `chevron-right`, `chevron-up`, `circle`,
  `circle-plus`, `crosshair`, `download`, `ellipsis`, `info`, `lock`, `maximize`, `minimize`,
  `plus`, `radio`, `share`, `smartphone`, `square`, `trash`, `upload`, `x`, `zoom-in`).
- **Copyright:** 2026 Lucide Icons and Contributors. Feather-derived icons: Copyright 2013-present
  Cole Bemis.

ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

The MIT License (MIT) (Feather-derived icons listed above)

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Official DJI Rec.709 cubes

The inherited Android asset set includes DJI D-Log / D-Log2 / D-Log M → Rec.709 cubes under
`Apps/Android/monitor/src/main/assets/luts/`. They remain compatibility assets from the
OpenPocketCine baseline and keep their original DJI attribution. The iOS app no longer bundles
them; its only camera look is the Insta360 Luna I-Log cube described below. No DJI profile is
presented as an Insta360 profile.

## Luna protocol references

The Luna bootstrap/framing research used `diamondfsd/luna-ai-cut`, inspected at
`ad47c16929b1b086c0a369fc2b4b5ece5b63f4df`, as an MIT-licensed implementation reference.
The project independently exercised its own authorization identity and verified camera
commands on local hardware. Source links, other references, license distinctions and
measurement provenance are recorded in
[`docs/research/insta360-protocol-sources.md`](docs/research/insta360-protocol-sources.md).
No official Insta360 SDK or proprietary protocol document is bundled.

MIT License

Copyright (c) 2026 diamondfsd

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Insta360 Luna I-Log rendering LUT

The unchanged manufacturer-supplied `Luna_I-Log_to_Rec709_BT1886_s33_v2.cube`
is included as a camera display conversion. It is version 2.0, dated 2026-05-20,
provided by the user on 2026-09-11. Copyright remains with the provider;
the application's source-code license does not relicense this resource.
No separate license accompanied the supplied folder. Source hashes and the
scope of the included asset are recorded in
[`Resources/CameraLUTs/README.md`](Resources/CameraLUTs/README.md) and its manifest.

## Build-resolved dependencies

Android's Gradle catalog records the versions of Kotlin/coroutines, AndroidX/Compose/Media3,
OkHttp, Kyant UI libraries and ML Kit used by the inherited native shell. See
[`Apps/Android/gradle/libs.versions.toml`](Apps/Android/gradle/libs.versions.toml) and the module
build files for the actual dependency declarations. Their upstream license metadata remains
with the resolved artifacts. This list of vendored-code/resource notices is not a claim to
be a complete release dependency bill of materials.

Font license copies are also bundled with Android in
`Apps/Android/monitor/src/main/assets/OFL-Sora.txt` and `OFL-IBMPlexSans.txt`.
