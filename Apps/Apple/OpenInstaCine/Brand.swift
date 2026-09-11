import Foundation
import MonitorUI
import MonitorCore

extension MonitorBrand {
    static let openInstaCine = MonitorBrand(
        displayName: "OpenInstaCine", monogram: "OIC", accentRGB: 0xFFCF00,
        cameraFamily: "Insta360 camera",
        discoveryHint: "Turn your Luna Ultra on and keep it nearby. Close the Insta360 app while connecting here.",
        protocolDescription: "Independent Luna connection over Bluetooth and camera Wi-Fi. Live preview is supported; camera controls are being added separately.",
        protocolLabel: "UCD2 / BLE + Wi-Fi",
        trademarkNotice: "An unofficial field monitor. Not affiliated with, endorsed by, or supported by Insta360. Insta360 and Luna are trademarks of their respective owners, used only to identify compatible cameras.",
        cameraLUTs: [
            .init(id: "insta360-luna-ilog-rec709-v2", title: "I-Log → Rec.709",
                  fileName: "Luna_I-Log_to_Rec709_BT1886_s33_v2.cube", inputTransfer: .ilog),
        ])
}
