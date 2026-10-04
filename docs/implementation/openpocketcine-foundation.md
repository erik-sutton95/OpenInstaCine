# OpenPocketCine foundation and OpenCine ownership

The app began with a Pocket source snapshot and Luna overlays. The copy-based
presentation-shell workflow is retired: its sync script, overlay script,
recipe and sync-commit stamp are removed.

## Current shared dependency

OpenCine at the sibling path ../OpenCine supplies the shared root, controls,
monitor presentation, operator settings, media models, native runtime and
Luna integration products declared in this app's manifests. The revision is
recorded in opencine-pins.txt and checked by scripts/checkout-opencine.sh.

Common behavior changes belong in the owning OpenCine package. Verify the
shared contract and actual app adapters before adopting a dependency revision.
Branding, entitlements, release configuration, secure storage and platform
composition remain app-owned.

## Remaining migration

Legacy app session projections and native adapters remain under review.
Retiring the source-sync tooling does not complete their ownership migration.
The supported Luna combinations and physical qualification limits remain
unchanged. See [implementation architecture](architecture.md) and
[development workflow](../DEVELOPMENT.md).

Earlier source snapshots and sync mechanics remain in this file's Git history.
