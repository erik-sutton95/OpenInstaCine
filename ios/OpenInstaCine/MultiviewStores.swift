import Foundation
import OpenCineAppKit
import Security

/// Device-only Multiview stage metadata: layout, selection, Fit/Fill and the camera Wi-Fi cleanup
/// record. The values and rules are OpenCine's `MultiviewStageJournal`; this keeps the Keychain
/// item and this app's tile count. Network passwords stay with the Luna setups' store.
enum MultiviewStageStore {
    static let service = "com.opencapture.openinstacine.multiview-stage"
    static var tileCount: Int { MultiviewSession.budget.qualifiedEntries ?? 4 }

    /// The coordinator's storage over this store.
    static var storage: MultiviewJournalStorage {
        MultiviewJournalStorage(load: { load() }, save: { save($0) })
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "stage",
        ]
    }

    static func load() -> MultiviewStageJournal.Stage? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess,
            let data = value as? Data
        else { return nil }
        return decode(data)
    }

    @discardableResult static func save(_ stage: MultiviewStageJournal.Stage?) -> Bool {
        guard let stage else {
            let deleted = SecItemDelete(query as CFDictionary)
            return deleted == errSecSuccess || deleted == errSecItemNotFound
        }
        guard let data = encode(stage) else { return false }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }

    /// The stored bytes of a stage valid for this app's tile count; nil otherwise.
    static func encode(_ stage: MultiviewStageJournal.Stage) -> Data? {
        guard stage.validated(tileCount: tileCount) != nil else { return nil }
        return try? JSONEncoder().encode(stage)
    }

    /// The stage stored bytes hold when they read and are valid for this app's tile count.
    static func decode(_ data: Data) -> MultiviewStageJournal.Stage? {
        (try? JSONDecoder().decode(MultiviewStageJournal.Stage.self, from: data))?
            .validated(tileCount: tileCount)
    }
}
