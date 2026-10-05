import Testing

@testable import OpenPocketViewCore

@Suite struct BleAdvertTests {
    // The real Osmo Pocket 4 Pro advert (new format): productType 0x00da = 218 -> model 0x22.
    // Classic format: model id in bytes [0:2], new-format flag (byte5 bit2) clear.
    /// #124 / #413: operator chrome follows captured body capabilities; everything
    /// without evidence fails closed.
    @Test func bodyCapabilitiesFailClosed() {
        for id in [0x20, 0x21, 0x22] {
            let pocket = CameraModel.resolve(modelId: id, name: nil)
            #expect(pocket.hasGimbal && pocket.supportsZoom, "\(pocket.name)")
            #expect(pocket.supportsTapFocus && pocket.supportsFocusMode, "\(pocket.name)")
        }
        let off: [CameraModel] = [
            .resolve(modelId: 0x19, name: nil),  // Nano
            .resolve(modelId: 0x15, name: nil),  // Action 5 Pro
            .resolve(modelId: 0x18, name: nil),  // Action 6: zoom `02/B8` encoding differs
            .resolve(modelId: 0x17, name: nil),  // 360
            .resolve(modelId: 0x70, name: nil),  // Mavic 3
            .resolve(modelId: 0x60, name: "Mystery"),  // unknown drone
            .resolve(modelId: nil, name: "Some Camera"),  // unknown body
            .default,
        ]
        for model in off {
            #expect(!model.hasGimbal, "\(model.name)")
            #expect(!model.supportsZoom, "\(model.name)")
            #expect(!model.supportsTapFocus, "\(model.name)")
            #expect(!model.supportsFocusMode, "\(model.name)")
        }
    }

}

@Suite struct CommandsTests {

}

@Suite struct CameraStatusTests {

}
