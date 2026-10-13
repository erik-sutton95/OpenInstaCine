# Decoder diagnostics

The shared monitor runtime records optional first-error context in local decoder
incidents: numeric status, ordered NAL types, byte count, IRAP and format-change
ages, and recent input rate. It contains no compressed frame bytes or camera
identity. Apple captures the access unit at the native decoder callback boundary;
Android codec-level failures leave per-access-unit context absent. Source reset
and retirement prevent old context from reaching a new source.

Existing reports remain readable without this optional field. Its presence helps
compare episodes; it does not prove where a damaged reference originated or
qualify recovery on physical hardware. Runtime ownership and cross-platform
limits are documented in the shared [runtime guide](../../OpenCine/docs/native-runtime/README.md).
