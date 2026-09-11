import SwiftUI

/// In-app legal pages. Canonical website copy lives at openpocketcine.app/privacy and /terms.
struct LegalDocumentView: View {
    @Environment(AppModel.self) private var model
    let kind: Kind
    var onClose: (() -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets

            ZStack(alignment: .topLeading) {
                LiveDesign.background

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MonitorIdentity.current.displayName)
                            .font(LiveType.ui(size: 9.5, weight: .bold))
                            .kerning(0.8)
                            .foregroundStyle(LiveDesign.accent)
                            .textCase(.uppercase)
                            .padding(
                                .leading,
                                OperatorPanelMetrics.closeButtonClearance(safeArea: insets))
                        Text(kind.title)
                            .font(LiveType.ui(size: 24, weight: .semibold))
                            .foregroundStyle(LiveDesign.text)
                            .padding(
                                .leading,
                                OperatorPanelMetrics.closeButtonClearance(safeArea: insets))
                    }

                    ScrollView {
                        Text(kind.body)
                            .font(LiveType.ui(size: 14, weight: .regular))
                            .foregroundStyle(LiveDesign.text)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                LiveDesign.surface,
                                in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                                    .stroke(LiveDesign.hairline, lineWidth: 1)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, OperatorPanelMetrics.topPadding(safeArea: insets))
                .padding(.leading, OperatorPanelMetrics.leadingPadding(safeArea: insets))
                .padding(.trailing, OperatorPanelMetrics.trailingPadding(safeArea: insets))
                .padding(.bottom, OperatorPanelMetrics.bottomPadding(safeArea: insets))

                CloseButton(action: dismiss, size: OperatorPanelMetrics.closeSize)
                    .padding(.leading, OperatorPanelMetrics.closeLeading)
                    .padding(.top, OperatorPanelMetrics.closeTopPadding(safeArea: insets))
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private func dismiss() {
        if let onClose {
            onClose()
        } else {
            model.homePanel = nil
        }
    }

    enum Kind: String, Identifiable {
        case privacy, terms, licenses, notice
        var id: String { rawValue }

        var title: String {
            switch self {
            case .privacy: "Privacy"
            case .terms: "Terms"
            case .licenses: "Licenses"
            case .notice: "NOTICE"
            }
        }

        var body: String {
            let brand = MonitorIdentity.current
            switch self {
            case .privacy:
                return """
                \(brand.displayName) connects to your \(brand.cameraFamily) over a local camera link. It does not create an account or send analytics, camera footage, or diagnostics to the developer automatically.

                What stays on this device
                • Saved camera names, operator preferences, and imported LUTs.
                • Camera authorization and Wi-Fi credentials in the system Keychain.
                • Media you choose to cache locally.

                Your live picture and camera traffic stay on the local link. On-device image analysis is not uploaded.

                Optional delivery
                Frame.io is optional and requires a configured build and your sign-in. Clips you select upload directly to Adobe. Authentication tokens stay in the Keychain. Saving to Photos, sharing files, and exporting diagnostics happen only when you choose those actions.

                Apple or Google may process permission prompts and platform diagnostics under their policies. Beta distribution services may share crash reports with the developer under their terms.
                """
            case .terms:
                return """
                \(brand.displayName) is free software under the Apache License 2.0. You may use, modify, and share it under that license.

                \(brand.trademarkNotice)

                Camera support is developed from observed protocol behavior. Only controls exposed as available are implemented. Record on the camera body while recording controls are unavailable.

                The software is provided on an AS IS BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND. See LICENSE in the repository.
                """
            case .licenses, .notice:
                return """
                \(brand.displayName)
                Copyright 2026 Erik Sutton and contributors

                Licensed under the Apache License, Version 2.0.
                https://www.apache.org/licenses/LICENSE-2.0

                The shared monitor engine is extracted from OpenPocketCine and follows OpenZCine. Existing source attribution is retained. The CubeLUT parser is adapted from OpenZCine (Apache 2.0).

                HUD icons: Lucide (ISC; Feather-derived glyphs also MIT).
                Typography: Sora and IBM Plex Sans (SIL Open Font License).
                See the bundled resources and THIRD-PARTY-NOTICES for full attribution.

                \(brand.trademarkNotice)
                No proprietary camera SDK is bundled or required.
                """
            }
        }
    }
}
