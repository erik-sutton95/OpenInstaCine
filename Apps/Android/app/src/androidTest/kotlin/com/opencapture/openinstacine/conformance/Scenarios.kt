package com.opencapture.openinstacine.conformance

import com.opencapture.monitorui.MonitorCapabilities
import com.opencapture.opencine.appuitesting.ConformanceApp
import com.opencapture.opencine.appuitesting.ConformanceProfile
import com.opencapture.openinstacine.MainActivity

/**
 * The shared conformance scenarios (docs/conformance/SCENARIOS.md) against the real launcher, staged
 * by the Debug review host with SIMULATED sources only. ConformanceCoverageTest fails when one is missing.
 */
class GalleryRoundTrip : com.opencapture.opencine.appuitesting.GalleryRoundTrip(InstaReview)

class ShareRoundTrip : com.opencapture.opencine.appuitesting.ShareRoundTrip(InstaReview)

class ConfirmationCancel : com.opencapture.opencine.appuitesting.ConfirmationCancel(InstaReview)

class ChromeEditReturn : com.opencapture.opencine.appuitesting.ChromeEditReturn(InstaReview)

class AccessibilityTraversal : com.opencapture.opencine.appuitesting.AccessibilityTraversal(InstaReview)

class ScreenMatrix : com.opencapture.opencine.appuitesting.ScreenMatrix(InstaReview)

class ConformanceCoverageTest : com.opencapture.opencine.appuitesting.ConformanceCoverageTest(InstaReview)

private object InstaReview : ConformanceApp {
    override val activity = MainActivity::class.java
    // This local library has no connected camera or optional camera services.
    override val profile = ConformanceProfile("InstaCine", MonitorCapabilities())
}
