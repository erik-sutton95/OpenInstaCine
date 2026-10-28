#!/usr/bin/env python3
"""Regression tests for scripts/ci-test-timing.py, on fixtures shaped like real CI output."""

import contextlib
import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path

# Loading the script must not leave a __pycache__ directory in the repository.
sys.dont_write_bytecode = True
SCRIPT = Path(__file__).with_name("ci-test-timing.py")
spec = importlib.util.spec_from_file_location("ci_test_timing", SCRIPT)
timing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(timing)

SWIFT_LOG = """\
Test Suite 'All tests' started at 2026-10-28 14:35:09.041.
◇ Suite "Gimbal repeatability on recorded moves" started.
✔ Test "A recorded move returns to its start" passed after 15.743 seconds.
✔ Test decodesEveryFrame(kind:) with 4 test cases passed after 0.198 seconds.
✘ Test "Every recorded move stays within tolerance" recorded an issue at GimbalRepeatabilityTests.swift:228:17
✘ Test "Every recorded move stays within tolerance" failed after 35.489 seconds with 1 issue.
➜ Test "Needs a gimbal" skipped: "no gimbal"
✘ Suite "Gimbal repeatability on recorded moves" failed after 35.490 seconds with 1 issue.
✔ Suite StatusWireTests passed after 2.362 seconds.
✘ Test run with 3 tests in 2 suites failed after 35.490 seconds with 1 issue.
✔ Test run with 32 tests in 5 suites passed after 2.362 seconds.
"""

XCTEST_LOG = """\
Test Suite 'Selected tests' started at 2026-10-27 20:21:15.938.
Test Suite 'OpenCinePackageTests.xctest' started at 2026-10-27 20:21:15.940.
Test Suite 'LunaCameraSessionTests' started at 2026-10-27 20:21:15.976.
Test Case '-[Insta360AppleTests.LunaCameraSessionTests testReconnects]' started.
Test Case '-[Insta360AppleTests.LunaCameraSessionTests testReconnects]' passed (3.120 seconds).
Test Case '-[Insta360AppleTests.LunaCameraSessionTests testRefusesUnknown]' failed (0.306 seconds).
Test Suite 'LunaCameraSessionTests' failed at 2026-10-27 20:21:19.409.
\t Executed 28 tests, with 1 failure (0 unexpected) in 3.426 (3.433) seconds
Test Suite 'LunaClockTests' started at 2026-10-27 20:21:19.409.
Test Suite 'LunaClockTests' passed at 2026-10-27 20:21:19.411.
\t Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.002) seconds
Test Suite 'OpenCinePackageTests.xctest' failed at 2026-10-27 20:21:19.953.
\t Executed 30 tests, with 1 failure (0 unexpected) in 3.427 (3.435) seconds
Test Suite 'Selected tests' failed at 2026-10-27 20:21:19.953.
\t Executed 30 tests, with 1 failure (0 unexpected) in 3.427 (3.435) seconds
"""

XCRESULT = {
    "testNodes": [
        {
            "name": "OpenInstaCine",
            "nodeType": "Test Plan",
            "children": [
                {
                    "name": "OpenInstaCineTests",
                    "nodeType": "Unit test bundle",
                    "children": [
                        {
                            "name": "MediaTimecodeTests",
                            "nodeType": "Test Suite",
                            "children": [
                                {
                                    "name": "testExport()",
                                    "nodeType": "Test Case",
                                    "result": "Passed",
                                    "durationInSeconds": 35.4,
                                },
                                {
                                    "name": "testSkip()",
                                    "nodeType": "Test Case",
                                    "result": "Skipped",
                                    "durationInSeconds": 0.1,
                                },
                            ],
                        },
                        {
                            "name": "PeakingTests",
                            "nodeType": "Test Suite",
                            "children": [
                                {
                                    "name": "Nested",
                                    "nodeType": "Test Suite",
                                    "children": [
                                        {
                                            "name": "matches()",
                                            "nodeType": "Test Case",
                                            "result": "Failed",
                                            "durationInSeconds": 2.0,
                                            "children": [
                                                {"name": "boom", "nodeType": "Failure Message"}
                                            ],
                                        },
                                    ],
                                },
                            ],
                        },
                    ],
                }
            ],
        }
    ],
}

GRADLE_TIMING = """\
:app:stageSwiftCore\t312000\tEXECUTED
:app:compileDebugKotlin\t95000\tEXECUTED
:opencine:insta360-luna:compileDebugKotlin\t41000\tFROM-CACHE
:app:testDebugUnitTest\t120500\tEXECUTED
:wear:preBuild\t1\tUP-TO-DATE
not a task line
"""

JUNIT = """<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="com.opencapture.openinstacine.FooTest" tests="4" skipped="1" failures="1"
    errors="0" time="3.25">
    <testcase name="a" classname="com.opencapture.openinstacine.FooTest" time="3.0"/>
</testsuite>
"""


class SwiftTestingTests(unittest.TestCase):
    def test_reports_runs_suites_and_results(self):
        out = timing.swift_testing(SWIFT_LOG)
        self.assertIn("3 tests in 2 suites failed after 35.5 s", out)
        self.assertIn("32 tests in 5 suites passed after 2.4 s", out)
        self.assertIn("2 passed, 1 failed, 1 skipped", out)
        self.assertIn("| decodesEveryFrame(kind:) | passed | 0.2 |", out)
        # Slowest suite first, display names and plain type names both parsed.
        self.assertLess(
            out.index("Gimbal repeatability on recorded moves | failed | 35.5"),
            out.index("StatusWireTests | passed | 2.4"),
        )
        self.assertNotIn("recorded an issue", out)

    def test_pipes_in_names_stay_inside_their_cell(self):
        out = timing.swift_testing(
            '✔ Test "a | b" passed after 1.0 seconds.\n'
            "✔ Test run with 1 test in 1 suite passed after 1.0 seconds.\n"
        )
        self.assertIn("| a \\| b | passed | 1.0 |", out)

    def test_empty_log_says_so(self):
        self.assertIn("No Swift Testing results", timing.swift_testing("Build complete!\n"))


class XCTestLogTests(unittest.TestCase):
    def test_reports_classes_without_the_aggregates(self):
        out = timing.xctest(XCTEST_LOG)
        self.assertIn("2 classes, 30 tests, 1 failed, 3.4 s summed", out)
        self.assertIn("| LunaCameraSessionTests | failed | 28 | 1 | 3.4 |", out)
        self.assertLess(out.index("LunaCameraSessionTests"), out.index("LunaClockTests"))
        self.assertNotIn("Selected tests", out)
        self.assertNotIn(".xctest", out)
        self.assertIn("| LunaCameraSessionTests testReconnects | passed | 3.1 |", out)
        self.assertIn("| LunaCameraSessionTests testRefusesUnknown | failed | 0.3 |", out)

    def test_swift_testing_only_log_has_no_xctest_table(self):
        # `swift test` prints an empty XCTest run around Swift Testing output.
        log = (
            "Test Suite 'All tests' passed at 2026-10-27 20:13:50.526.\n"
            "\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.006) seconds\n"
            + SWIFT_LOG
        )
        self.assertEqual(timing.xctest(log), "")

    def test_mixed_log_prints_both_tables(self):
        with tempfile.TemporaryDirectory() as root:
            log = Path(root, "swift-test.log")
            log.write_text(SWIFT_LOG + XCTEST_LOG)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(timing.main(["swift-testing", str(log)]), 0)
        self.assertIn("### Swift package tests\n", output.getvalue())
        self.assertIn("### Swift package tests (XCTest)", output.getvalue())


class XcresultTests(unittest.TestCase):
    def test_groups_cases_by_outermost_suite(self):
        out = timing.xcresult("OpenInstaCine.xcresult", XCRESULT)
        self.assertIn("3 test cases: 1 failed, 1 passed, 1 skipped", out)
        self.assertIn("| MediaTimecodeTests | 2 | 0 | 1 | 35.5 |", out)
        self.assertIn("| PeakingTests | 1 | 1 | 0 | 2.0 |", out)
        self.assertIn("| MediaTimecodeTests/testExport() | Passed | 35.4 |", out)

    def test_missing_bundle_says_so(self):
        with tempfile.TemporaryDirectory() as root:
            missing = Path(root, "Quarantined.xcresult")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(timing.main(["xcresult", str(missing)]), 0)
        self.assertIn("### Quarantined.xcresult", output.getvalue())
        self.assertIn("did not happen", output.getvalue())

    def test_empty_bundle_says_so(self):
        self.assertIn("No test cases", timing.xcresult("x.xcresult", {"testNodes": []}))


class GradleTests(unittest.TestCase):
    def test_tasks_sorted_and_grouped_by_name(self):
        out = timing.gradle_tasks(GRADLE_TIMING)
        self.assertIn("5 tasks: 3 executed, 1 from-cache, 1 up-to-date", out)
        self.assertLess(
            out.index(":app:stageSwiftCore | EXECUTED | 312.0"),
            out.index(":app:testDebugUnitTest | EXECUTED | 120.5"),
        )
        self.assertIn("| compileDebugKotlin | 2 | 136.0 |", out)

    def test_junit_suites_by_module(self):
        with tempfile.TemporaryDirectory() as root:
            report = Path(root, "app/build/test-results/testDebugUnitTest/TEST-Foo.xml")
            report.parent.mkdir(parents=True)
            report.write_text(JUNIT)
            out = timing.junit_suites([report])
        self.assertIn("1 suites, 4 tests, 1 failed, 1 skipped, 3.2 s summed", out)
        self.assertIn("| app testDebugUnitTest | 1 | 4 | 3.2 |", out)
        self.assertIn(
            "| com.opencapture.openinstacine.FooTest | app testDebugUnitTest | 4 | 1 | 3.2 |", out
        )

    def test_missing_inputs_say_so(self):
        self.assertIn("No task timings", timing.gradle_tasks(""))
        self.assertIn("No JUnit reports", timing.junit_suites([]))


if __name__ == "__main__":
    unittest.main()
