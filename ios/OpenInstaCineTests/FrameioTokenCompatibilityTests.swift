import Foundation
import OpenCineFrameIO
import OpenCineFrameIOApple
import XCTest

@testable import OpenInstaCine

final class FrameioTokenCompatibilityTests: XCTestCase {
    func testPreviouslySavedTokensKeepTheirJSONShapeAndExpiry() throws {
        // These are the JSONEncoder shapes persisted by the app before adopting the shared
        // client, including a sign-in that did not supply a refresh token.
        let fixtures = [
            #"{"token":{"access_token":"fixture-access","refresh_token":"fixture-refresh","expires_in":3600,"token_type":"Bearer"},"receivedAt":123456}"#,
            #"{"token":{"access_token":"fixture-access","expires_in":3600,"token_type":"Bearer"},"receivedAt":123456}"#,
        ]
        for fixture in fixtures {
            let original = Data(fixture.utf8)
            let stored = try JSONDecoder().decode(StoredFrameioToken.self, from: original)
            XCTAssertEqual(stored.token.accessToken, "fixture-access")
            XCTAssertEqual(stored.token.expiresIn, 3600)
            XCTAssertEqual(stored.receivedAt, Date(timeIntervalSinceReferenceDate: 123456))
            XCTAssertEqual(stored.accessExpiry, Date(timeIntervalSinceReferenceDate: 127056))
            let encoded = try JSONEncoder().encode(stored)
            XCTAssertEqual(
                try JSONSerialization.jsonObject(with: encoded) as? NSDictionary,
                try JSONSerialization.jsonObject(with: original) as? NSDictionary)
        }
    }

    /// A2-57: the shared Frame.io account keeps Insta's keychain item, destination key and
    /// history key, so saved sign-ins and projects survive.
    @MainActor func testTokenDestinationAndHistoryStayInInstaNamespaces() {
        let model = AppModel()
        XCTAssertEqual(model.frameio.tokens.service, "OpenInstaCine.frameio")
        XCTAssertEqual(model.frameio.tokens.account, "oauth-token")
        XCTAssertEqual(model.frameio.destinations.key, "opc.frameio.destination.v1")
        XCTAssertEqual(FrameioHostNamespace.openInstaCine.historyKey, "opc.frameio.uploaded.v1")
    }
}
