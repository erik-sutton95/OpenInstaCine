import MonitorPresentation
import MonitorUI
import SwiftUI
import UIKit

/// OpenInstaCine brand palette: Luna yellow on black.
enum BrandColors {
    static let background = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
    static let backgroundDeep = Color(red: 14 / 255, green: 14 / 255, blue: 14 / 255)
    static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255)
    static let ink = Color.white
    static let muted = Color(red: 160 / 255, green: 165 / 255, blue: 165 / 255)
    static var accent: Color { MonitorTheme.accent }
    static var accentSoft: Color { MonitorTheme.accent.opacity(0.18) }
}

/// App mark from the AppLogo raster; falls back to a drawn monogram.
struct OPCMonogramMark: View {
    var size: CGFloat = 72

    var body: some View {
        let cornerRadius = size * 0.22
        Group {
            if let logo = UIImage(named: "AppLogo") ?? UIImage(named: "AppLogo.png") {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(BrandColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                BrandColors.accent.opacity(0.55), lineWidth: max(1, size * 0.018))
                    )
                    .overlay {
                        Text("OPC")
                            .font(MonitorTheme.font(size * 0.34, weight: .heavy))
                            .kerning(size * 0.02)
                            .foregroundStyle(BrandColors.accent)
                    }
                    .frame(width: size, height: size)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: size * 0.08, y: size * 0.04)
        .accessibilityLabel("OpenInstaCine")
    }
}

struct OpenInstaCineWordmark: View {
    var fontSize: CGFloat = 34
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.18) {
            Text("OpenInstaCine")
                .font(MonitorTheme.font(fontSize, weight: .bold))
                .foregroundStyle(BrandColors.ink)
            if let subtitle {
                Text(subtitle)
                    .font(MonitorTheme.font(fontSize * 0.38, weight: .medium))
                    .foregroundStyle(BrandColors.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum LaunchSplashTiming {
    static let visibleDuration = MonitorLaunchTiming.visibleDuration
    static let fadeOutDuration = MonitorLaunchTiming.fadeOutDuration
}

struct BrandBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 8 / 255, green: 8 / 255, blue: 8 / 255),
                    Color(red: 14 / 255, green: 14 / 255, blue: 14 / 255),
                    Color(red: 8 / 255, green: 8 / 255, blue: 8 / 255),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 120 / 255, green: 102 / 255, blue: 70 / 255).opacity(0.28),
                    .clear,
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

struct LaunchSplashContent: View {
    var compact: Bool = false

    var body: some View {
        MonitorLaunchSplashContent(
            compact: compact,
            backdrop: { BrandBackdrop() },
            mark: { OPCMonogramMark(size: $0) },
            wordmark: { OpenInstaCineWordmark(fontSize: $0) })
    }
}

struct LaunchSplashOverlay: View {
    @Binding var isVisible: Bool

    var body: some View {
        MonitorLaunchSplashOverlay(isVisible: $isVisible) {
            LaunchSplashContent()
        }
    }
}
