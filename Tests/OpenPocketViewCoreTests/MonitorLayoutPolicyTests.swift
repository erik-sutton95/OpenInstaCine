import Testing

@testable import OpenPocketViewCore

@Suite struct MonitorLayoutPolicyTests {
    @Test func horizontalLayoutDirectionUsesDeviceOrientationBeforeSafeAreaFallback() {
        let ambiguousSafeArea = MonitorEdgeInsets(top: 0, leading: 44, bottom: 21, trailing: 44)

        #expect(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .landscapeLeft,
                safeArea: ambiguousSafeArea
            ) == .standard
        )
        #expect(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .landscapeRight,
                safeArea: ambiguousSafeArea
            ) == .mirrored
        )
        #expect(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .unknown,
                safeArea: MonitorEdgeInsets(top: 0, leading: 44, bottom: 21, trailing: 59)
            ) == .mirrored
        )
    }

    @Test func horizontalLayoutDirectionKeepsPortraitAndLandscapeLeftStandard() {
        let trailingCutout = MonitorEdgeInsets(top: 0, leading: 44, bottom: 21, trailing: 59)

        #expect(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .portrait,
                safeArea: trailingCutout
            ) == .standard
        )
        #expect(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .portraitUpsideDown,
                safeArea: trailingCutout
            ) == .standard
        )
        #expect(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .landscapeLeft,
                safeArea: trailingCutout
            ) == .standard
        )
    }

    @Test func horizontalLayoutDirectionUnknownFallsBackToDominantCutout() {
        let leadingCutout = MonitorEdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 44)
        let trailingCutout = MonitorEdgeInsets(top: 0, leading: 44, bottom: 21, trailing: 59)
        let cornerPadding = MonitorEdgeInsets(top: 0, leading: 44, bottom: 21, trailing: 44)

        #expect(MonitorHorizontalLayoutDirection.resolve(for: leadingCutout) == .standard)
        #expect(MonitorHorizontalLayoutDirection.resolve(for: trailingCutout) == .mirrored)
        // 44pt is corner padding, not a cutout — neither side wins.
        #expect(MonitorHorizontalLayoutDirection.resolve(for: cornerPadding) == .standard)
        #expect(
            MonitorHorizontalLayoutDirection.resolve(
                deviceOrientation: .unknown,
                safeArea: leadingCutout
            ) == .standard
        )
    }

    /// Landscape-right feed + chrome share one horizontal mirror at the exit.
    @Test func landscapeRightMirrorsFeedAndChromeTogether() {
        let viewportWidth = 844.0
        let feed = MonitorFeedFrame(x: 59, y: 0, width: 693.333, height: 390)
        let chrome = MonitorLayoutRegion(x: 16, y: 14, width: 82.8, height: 362)

        let mirroredFeed = feed.mirroredHorizontally(in: viewportWidth)
        let mirroredChrome = chrome.mirroredHorizontally(in: viewportWidth)

        #expect(abs(mirroredFeed.x - (viewportWidth - feed.x - feed.width)) < 0.001)
        #expect(mirroredFeed.y == feed.y)
        #expect(mirroredFeed.width == feed.width)
        #expect(mirroredFeed.height == feed.height)
        #expect(abs(mirroredChrome.x - (viewportWidth - chrome.x - chrome.width)) < 0.001)
        #expect(mirroredChrome.y == chrome.y)
        #expect(mirroredChrome.width == chrome.width)
        #expect(mirroredChrome.height == chrome.height)
    }

    @Test func layoutRegionExposesMaxAndMidAnchors() {
        let region = MonitorLayoutRegion(x: 100, y: 20, width: 300, height: 200)

        #expect(region.maxX == 400)
        #expect(region.maxY == 220)
        #expect(region.midX == 250)
        #expect(region.midY == 120)
    }
}
