import Foundation
import OpenCineFrameIO
import Security

typealias StoredFrameioToken = OpenCineFrameIO.StoredFrameioToken

/// Reads the Frame.io OAuth configuration from Info.plist. Register an OAuth Single Page App in the
/// Adobe Developer Console (Frame.io API on the project) and set `FrameioClientID` + `FrameioRedirectURI`.
enum FrameioConfig {
    static var configuration: FrameioConfiguration? {
        guard
            let clientID = info("FrameioClientID"), !clientID.isEmpty,
            let redirect = info("FrameioRedirectURI"), !redirect.isEmpty
        else { return nil }
        return FrameioConfiguration(clientID: clientID, redirectURI: redirect)
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}

/// Keychain-backed store for the Frame.io token. Never logs token values.
enum FrameioTokenStore {
    private static let service = "OpenInstaCine.frameio"
    private static let account = "oauth-token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ stored: StoredFrameioToken) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> StoredFrameioToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let stored = try? JSONDecoder().decode(StoredFrameioToken.self, from: data)
        else { return nil }
        return stored
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static var isConnected: Bool { load() != nil }
}

/// Bridges the existing app credential namespace to the shared client.
private struct FrameioKeychainStorage: FrameioTokenStorage {
    func load() -> StoredFrameioToken? { FrameioTokenStore.load() }
    func save(_ stored: StoredFrameioToken) { FrameioTokenStore.save(stored) }
    func clear() { FrameioTokenStore.clear() }
}

/// The app supplies identity, credential storage and its platform HTTPS policy.
/// All OAuth exchange, API and upload work runs in OpenCineFrameIO.
enum FrameioClients {
    static func make(
        config: FrameioConfiguration,
        transport: any FrameioHTTPTransport = FrameioURLSessionTransport.interactive
    ) -> FrameioClient {
        FrameioClient(config: config, transport: transport, tokens: FrameioKeychainStorage())
    }
}
