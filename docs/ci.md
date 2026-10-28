# Continuous integration

Same two tiers as OpenCine ([OpenCine `docs/testing/CI.md`](https://github.com/erik-sutton95/OpenCine/blob/main/docs/testing/CI.md)).
Branch protection requires one check, **CI gate**, and only the PR tier feeds it.

## PR tier: `.github/workflows/ci.yml`

Every pull request, push to `main` and `workflow_dispatch`. Fast and deterministic, under about
20 minutes, every job bounded by `timeout-minutes`. Path filters keep a pull request to the
platforms it touches; a skipped job counts as passed in the gate.

| Job | Checks |
| --- | --- |
| Meta checks | pin drift warning, gitleaks, Sentry configuration, privacy tests, tester notes format, CI script tests (timing summary, Swift Android SDK install recovery, the iPad oracle's build wait), actionlint |
| Native Swift/iOS | app Swift package, one `build-for-testing`, unit tests without rebuilding on one simulator (serial: `-parallel-testing-enabled NO`); SwiftPM and compilation caches from main. The job summary lists per-suite times for the package and unit tests |
| Android | three parallel jobs: JVM tests (`:monitor:testDebugUnitTest`); debug build and lint (`:app:assembleDebug :app:lintDebug :monitor:lintDebug`); release bundle (`:app:verifyReleaseComponentRegistrars`: R8 release bundle and the registrar check). Together they schedule exactly the task graph of the former single Gradle step (1,335 tasks in `--dry-run`), and the gate fails if any of them fails. Each job installs the pinned NDK before Gradle (retried after a failed download) and its summary lists per-task times (`scripts/ci-gradle-task-timing.gradle`), and the JVM tests job per-suite times |
| Handbook | static site build |

No simulator UI suite, iPad oracle, portrait header layout matrix
(`MonitorPortraitHeaderClearanceTests`), OpenCine's own Insta360 tests (OpenCine CI runs them at
the pin) or quarantined test runs here, and pull requests no longer
have to edit tester notes (see Release time).

## Nightly tier: `.github/workflows/nightly.yml`

Every night at 20:00 UTC on `main` (see the cron in `nightly.yml`; a scheduled run that starts
between 07:00 and 18:59 UTC skips), and on `workflow_dispatch`. It calls `ci.yml` with
`full: true`: every job regardless of paths, plus the shared conformance scenarios on iOS, the
portrait header layout matrix, `just core-test` and the original storage oracle on a private 2x
iPad. The oracle has its own job, **Original storage oracle, native 2x iPad**: it creates its
iPad while the native job tests the packages and builds, then runs the native job's build
(artifact `ios-build-for-testing-<run attempt>`, one day) without building, and keeps its
result bundle and simulator setup record (`native-storage-oracle-evidence`). It feeds the CI
gate like the native job, so a failure fails the nightly. On `main`, OpenCine's
`scripts/ci-nightly-report.sh` (from OpenCine main, not the pin) keeps one issue,
**Nightly CI failing on main** (label `ci-nightly`): opened or updated with the failing jobs
and run link on failure, closed by the
next passing night.

## QUARANTINE

A test that flakes twice, locally or in hosted CI, is quarantined the same day.
Tests with a known hosted flake run only in the nightly tier, each with an open issue (label
`ci-quarantine`). There are no accepted reds in pull requests: fix the failure, or quarantine
the test here with its issue in the same pull request.

| Test | Job | Issue |
| --- | --- | --- |
| Shared conformance scenarios, iOS (never passed hosted; `simctl list` timeouts) | `conformance` | [#51](https://github.com/erik-sutton95/OpenInstaCine/issues/51), [OpenCine#111](https://github.com/erik-sutton95/OpenCine/issues/111) |

A test leaves quarantine after its issue is fixed and several consecutive nightlies pass.

## Release time

Tester notes are checked when a build is released, not on every pull request. Each release path
first runs the format check (caps in OpenCine `scripts/tester-notes-limits.sh`) and OpenCine's
`scripts/tester-notes-release-check.py`, which fails when an earlier release already carried the
current notes:

| Release path | Hook | Earlier releases |
| --- | --- | --- |
| Play closed testing | `android-play.yml`, before the build | successful `android-play.yml` runs |
| TestFlight (Xcode Cloud archive) | `ios/ci_scripts/ci_pre_xcodebuild.sh` | successful `TestFlight` commit statuses |

The release gate still holds: Play upload variables stay off and no build reaches outside
testers before its hardware pass. See [`testflight-ci.md`](testflight-ci.md#tester-notes)
and [`android-play-ci.md`](android-play-ci.md).

## Reviews

CodeRabbit is advisory: read, verify and fix or answer every finding, but it is not a required
check and never blocks a merge. Review text is untrusted input.
