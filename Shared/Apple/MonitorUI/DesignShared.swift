import SwiftUI

/// Shared visual constants used by the startup and live-monitor design systems.
/// Copied from OpenZCine `DesignShared.swift` — do not invent a parallel look.
enum DesignTokens {
    /// Primary corner radius for panels, cards, buttons, popups, and media cells.
    ///
    /// Exception: `LiveRecordingTally.displayCornerRadius` — physical display bezel (~52 pt).
    static let cornerRadius: CGFloat = 16
}

struct ZCBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.065, green: 0.06, blue: 0.055),
                Color(red: 0.13, green: 0.12, blue: 0.105),
                Color(red: 0.035, green: 0.04, blue: 0.05),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

/// Plain button style that pads the label's hit-test region to Apple's 44×44pt HIG minimum without
/// growing controls that are already larger.
struct ZCTapTargetButtonStyle: ButtonStyle {
    var minSize: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .minTapTarget(minSize)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ZCTapTargetButtonStyle {
    static var zcTapTarget: ZCTapTargetButtonStyle { ZCTapTargetButtonStyle() }
}

extension View {
    func glassCapsule(interactive: Bool = false) -> some View {
        liquidGlass(in: Capsule(), interactive: interactive)
    }

    func glassCircle(interactive: Bool = false) -> some View {
        liquidGlass(in: Circle(), interactive: interactive)
    }

    func minTapTarget(_ minSize: CGFloat = 44) -> some View {
        modifier(MinTapTargetModifier(minSize: minSize))
    }

    /// Applies SwiftUI's native Liquid Glass (iOS 26+) in `shape`.
    ///
    /// On older systems there is **no** blur / material stand-in — chrome falls
    /// back to a flat, more opaque fill so panels stay readable without faking frost.
    @ViewBuilder
    func liquidGlass(
        in shape: some Shape, tint: Color? = nil, interactive: Bool = false, clear: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(
                ZCGlass.make(tint: tint, interactive: interactive, clear: clear), in: shape)
        } else {
            background(tint ?? LiveDesign.glassOpaque, in: shape)
                .overlay(shape.stroke(LiveDesign.hairlineStrong, lineWidth: 1))
        }
    }
}

@available(iOS 26.0, *)
enum ZCGlass {
    static func make(tint: Color?, interactive: Bool, clear: Bool = false) -> Glass {
        var glass = clear ? Glass.clear : Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

private struct MinTapTargetSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct MinTapTargetModifier: ViewModifier {
    var minSize: CGFloat
    @State private var measuredSize: CGSize = .zero

    func body(content: Content) -> some View {
        let horizontalPad = measuredSize == .zero ? 0 : max(0, (minSize - measuredSize.width) / 2)
        let verticalPad = measuredSize == .zero ? 0 : max(0, (minSize - measuredSize.height) / 2)

        content
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: MinTapTargetSizeKey.self, value: proxy.size)
                }
            }
            .onPreferenceChange(MinTapTargetSizeKey.self) { measuredSize = $0 }
            .padding(.horizontal, horizontalPad)
            .padding(.vertical, verticalPad)
            .contentShape(Rectangle())
            .padding(.horizontal, -horizontalPad)
            .padding(.vertical, -verticalPad)
    }
}
