import Foundation
import OpenPocketCineAndroidFacade
import OpenPocketViewCore
import Testing

@Suite
struct AndroidSessionWireTests {
    /// Each field round-trips on its own, so one dropped on both encode and
    /// decode still fails here even though the idempotence test passes.
    /// Zoom stops, with or without trailing `.0`, plus gimbal and zoom support
    /// (nil when this body's capabilities are not asserted).
    @Test
    func feedRepairDecisionsMatchCore() {
        func step(_ start: Double, _ irap: String, _ requests: Int) -> String {
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "decoderRepairStep",
                requestJSON:
                    "{\"secondsSinceRepairStart\":\(start),\"secondsSinceLastEnable\":2,"
                    + "\"secondsSinceLastIrap\":\(irap),\"keyframeRequests\":\(requests)}")
        }
        #expect(step(2, "null", 1) == "resendKeyframe")
        #expect(step(4, "0.4", 2) == "wait")
        #expect(step(4, "null", 2) == "rebuildEndpoint")
        #expect(step(16, "null", 1) == "deadline")
        func hold(_ previous: Int, _ picture: Bool, _ video: String) -> String {
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "nextSessionHoldCycles",
                requestJSON:
                    "{\"lastVideoPacketAge\":\(video),\"previousCycles\":\(previous),"
                    + "\"pictureSinceLastCycle\":\(picture)}")
        }
        #expect(hold(0, false, "0.1") == "1")
        #expect(hold(2, false, "0.1") == "0", "third cycle releases Bluetooth")
        #expect(hold(2, true, "0.1") == "1")
        #expect(hold(0, false, "null") == "0")
    }

    @Test
    func cameraSoftAPHandshakeTimeoutMatchesCore() {
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "handshakeTimeoutStep",
                requestJSON: "{\"pathReady\":true,\"rebindsUsed\":0,\"inboundDatagrams\":0}"
            )
                == CameraSoftAP.handshakeTimeoutStep(
                    pathReady: true, rebindsUsed: 0, inboundDatagrams: 0
                ).rawValue)
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "handshakeTimeoutStep",
                requestJSON: "{\"pathReady\":true,\"rebindsUsed\":0,\"inboundDatagrams\":1}"
            ) == "keepSocket")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "handshakeTimeoutStep",
                requestJSON: "{\"pathReady\":false,\"rebindsUsed\":0,\"inboundDatagrams\":0}"
            ) == "fail")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "handshakeTimeoutStep",
                requestJSON:
                    "{\"pathReady\":true,\"rebindsUsed\":\(CameraSoftAP.handshakeRebindLimit),\"inboundDatagrams\":0}"
            ) == "fail")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldKickAfterHandshakeTimeout",
                requestJSON: "{\"pathReady\":true}"
            ) == "false")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldKickAfterHandshakeTimeout",
                requestJSON: "{\"pathReady\":false}"
            ) == "true")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldGiveUpOpenRetry",
                requestJSON: "{\"attempts\":5}"
            ) == "false")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldGiveUpOpenRetry",
                requestJSON: "{\"attempts\":6}"
            ) == "true")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "canSendHandshake",
                requestJSON: "{\"receiveArmed\":false,\"connectionReady\":true}"
            ) == "false")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "canSendHandshake",
                requestJSON: "{\"receiveArmed\":true,\"connectionReady\":false}"
            ) == "false")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "canSendHandshake",
                requestJSON: "{\"receiveArmed\":true,\"connectionReady\":true}"
            ) == "true")
    }

    @Test
    func cameraSoftAPFirstPictureMatchesCore() {
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "firstPictureStep",
                requestJSON:
                    "{\"videoPackets\":0,\"enableSends\":0,\"secondsSinceLastEnable\":0,\"hasPresentedPicture\":false}"
            ) == "resendEnable")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "firstPictureStep",
                requestJSON:
                    "{\"videoPackets\":0,\"enableSends\":1,\"secondsSinceLastEnable\":3,\"hasPresentedPicture\":false}"
            ) == "wait")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "firstPictureStep",
                requestJSON:
                    "{\"videoPackets\":0,\"enableSends\":1,\"secondsSinceLastEnable\":9,\"hasPresentedPicture\":false}"
            )
                == CameraSoftAP.firstPictureStep(
                    videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 9
                ).rawValue)
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "firstPictureStep",
                requestJSON:
                    "{\"videoPackets\":0,\"enableSends\":1,\"secondsSinceLastEnable\":9,\"hasPresentedPicture\":true}"
            ) == "wait")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldForceEnableAfterUDPRebuild",
                requestJSON: "{\"hadVideo\":true}"
            ) == "false")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldForceEnableAfterUDPRebuild",
                requestJSON: "{\"hadVideo\":false}"
            ) == "true")
    }
}
