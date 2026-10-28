# Contributing to OpenInstaCine

Contributions are welcome. By participating, you agree to our
[Code of Conduct](CODE_OF_CONDUCT.md).

## Getting set up

Install `just`, Xcode 26 and XcodeGen for iOS work. Android work also needs
Android Studio, Java and the Swift Android SDK described in
[`docs/android-play-ci.md`](docs/android-play-ci.md). Check out the pinned
OpenCine dependency before generating or building either app:

```sh
scripts/checkout-opencine.sh
just check
```

The dependency lives at `../OpenCine`, at the exact commit in
`opencine-pins.txt`. An existing checkout is compared rather than moved.
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) describes the layout, Simulator
rig and lab tooling. Real pairing requires a physical phone and Luna Ultra.

## Workflow and checks

Open a pull request into `main` and fill in the PR template. Use Conventional
Commits. The required hosted status check is **CI gate**; it includes the
app's metadata, native, Android and handbook jobs, with deliberate path-based
skips; the full suite runs nightly ([`docs/ci.md`](docs/ci.md)). Repository
settings are documented in [`docs/repository-settings.md`](docs/repository-settings.md).
CodeRabbit reviews are advisory: address every finding, but it never blocks a merge.

`just check` runs the existing research/tooling and metadata checks. For
native changes, also run the relevant existing recipes: `just core-test`,
`just ios-test`, `just ios-build` or `just android-check`. State which checks
ran and which device behavior remains untested. Do not treat a simulator or
compile pass as proof of camera behavior.

Keep public docs and setup instructions current with the change. Camera
protocol and common monitor behavior belong in their owning OpenCine
packages; this app composes the Luna integration and app services. Preserve
existing native fixtures and golden assertions.

Tester notes are replaced once per release, not in feature pull requests;
TestFlight and Play releases fail while they are stale. Use
`just tester-notes-window`; follow
[`docs/testflight-ci.md`](docs/testflight-ci.md),
[`docs/android-play-ci.md`](docs/android-play-ci.md) and
[`docs/RELEASE.md`](docs/RELEASE.md).

## Writing tests

Test behavior at contract boundaries, not implementation. A test earns its place when a real
regression fails it and a correct refactor does not. Tests that pin implementation lock in
whatever code exists today and cost every later change (and every agent) time and tokens.

- One test per behavior that the operator, a camera or another app depends on: camera commands
  and the bytes they put on the wire, recording start and stop, preservation of footage and user
  data, session recovery, migrations, and shared UI contracts (what is shown, announced and
  tappable). Not one test per function or type.
- Do not test private helpers, call order, file or type names, source text or exact internal
  counts, and do not reach into private state through reflection. Do not copy an old
  implementation into a test as its oracle; use golden data or recorded camera output.
- Before adding a test, check whether an existing test already fails for the same bug. Extend it
  instead of adding a near-duplicate.
- Deterministic only: manual clocks and event signals, no sleeps, wall-clock budgets or fixed
  yield loops. A performance requirement is an operation count in normal tests; real timing
  budgets belong in a performance tier.
- A test that flakes twice is quarantined with an issue the same day (see the CI quarantine
  rule), not diagnosed again run after run.
- A test that fails a correct refactor is pinning implementation. Replace it with a behavior test
  that catches the same bug, then delete it in the same change. That deletion is not lost
  coverage.
- Keep: wire and migration goldens, recovery and decoder ownership tests, real-camera corpora,
  Swift and Kotlin twins (they test two shipping implementations), and architecture rules on
  imports, dependency edges and brand-free shared code (they guard a boundary, not an
  implementation detail).

## Issues, ideas and private material

Use the [bug form](https://github.com/erik-sutton95/OpenInstaCine/issues/new?template=bug_report.yml)
for bugs and [Discussions](https://github.com/erik-sutton95/OpenInstaCine/discussions)
for ideas and questions. Security reports follow [`SECURITY.md`](SECURITY.md).

Do not commit camera Wi-Fi passwords, approval identities, signing keys,
private captures, footage or local cloud credentials. Follow
[`docs/commit-hygiene.md`](docs/commit-hygiene.md). Optional Frame.io and
reliability configuration stays in ignored local files; example files must
contain placeholders. Keep the existing provider LUT attribution and
third-party license notices.
