---
title: Keeping docs current
description: Public handbook vs repo research notes. What to update in the same change so opencapture.org/openinstacine/docs stays accurate.
---

The public site at
[opencapture.org/openinstacine/docs](https://opencapture.org/openinstacine/docs/)
is this Starlight handbook. It must stay current with the apps and the protocol.
That is a same-change rule, not a follow-up.

## Two layers

| Layer | Path | Who it is for | Published? |
| --- | --- | --- | --- |
| **Public handbook** | `handbook/src/content/docs/` | Operators, new contributors, anyone on the website | Yes, `/openinstacine/docs/` |
| **Research and status notes** | `docs/`, `docs/research/`, `docs/implementation/` | Maintainers and agents: dated capture logs, verification records, parity ledgers | No (readable on GitHub) |

Do not paste research logs, capture paths, Wi-Fi passwords, approval
identities, serial numbers or packet captures into the handbook. Summarize the
finding and link the repo note. Common wire facts live under
[Shared protocol](../../protocol/connection/). Model-specific command values,
firmware restrictions and capture findings belong under
[Insta360 Devices](../../devices/).

## What to update when

| You changed | Update in the same change |
| --- | --- |
| UCD2 framing, BLE bootstrap, crypto, transport | The matching page under `handbook/src/content/docs/protocol/` |
| A command value, option number, firmware restriction | The matching page under `handbook/src/content/docs/devices/luna-ultra/`, and the [command catalog](../../protocol/commands/) if it is a shared definition |
| Operator-visible chrome, assists, connection UX | [`docs/implementation/luna-ios-status.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/implementation/luna-ios-status.md) **and** the [iOS](../../apps/ios/) or [Android](../../apps/android/) page |
| Build, toolchain, how to run | [Setup](../../guides/setup/) and [`docs/DEVELOPMENT.md`](https://github.com/erik-sutton95/OpenInstaCine/blob/main/docs/DEVELOPMENT.md) |
| Architecture seams (core vs adapter vs shell) | [Architecture](../../apps/architecture/) |
| TestFlight or Play tester notes | `ios/TestFlight/WhatToTest.en-US.txt`, `Apps/Android/Play/` (the this-build window; not the handbook) |
| An open-beta release | A page under [Release notes](../../releases/0-1-0/) |
| Pairing or live-view operator FAQ | [Troubleshooting](../../guides/troubleshooting/) |

A task is not done until those pages match the code.

## Build and preview

```bash
cd handbook
npm ci
npm run dev                                       # http://localhost:4321/
HANDBOOK_BASE=/openinstacine/docs npm run build   # as published
```

CI builds the handbook with the published base path whenever `handbook/`
changes. Relative links resolve from the final trailing-slash URL, not the
Markdown file path. Links to the product, privacy and support pages are
absolute (`https://opencapture.org/openinstacine/...`), because the handbook is
served under a sub-path of that site. A merge to `main` that touches `handbook/`
triggers a redeploy of opencapture.org.

## Style

- No em dash characters. Use commas, colons, periods or parentheses.
- Keep evidence labels (Observed, Verified, Source-backed, Unknown) attached to
  protocol claims.
- Link repository files with
  `https://github.com/erik-sutton95/OpenInstaCine/blob/main/...` URLs.
