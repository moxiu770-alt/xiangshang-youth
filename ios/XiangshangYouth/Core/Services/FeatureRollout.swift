import Foundation
import Security

/// Product-facing flags use a deterministic installation bucket. The ID never
/// leaves the device; a remote config supplies only public rollout rules.
@MainActor
final class FeatureRollout: ObservableObject {
    enum Feature: String { case growthInsights }

    private struct Rule: Codable { let key: String; let enabled: Bool; let rolloutPercent: Int }
    private struct Payload: Codable { let revision: String; let features: [Rule] }

    @Published private(set) var revision = "bundled"
    private var rules: [String: Rule] = [
        Feature.growthInsights.rawValue: Rule(key: Feature.growthInsights.rawValue, enabled: true, rolloutPercent: 100)
    ]
    private let defaults = UserDefaults.standard
    private let installationKey = "xiangshang.rollout.installation-id"
    private let keychainService = "com.xiangshang.youth.rollout"
    private let cachedPayloadKey = "xiangshang.rollout.cached-payload"
    private var volatileInstallationID: String?

    init() { restoreCache() }

    func isEnabled(_ feature: Feature) -> Bool {
        if let override = ProcessInfo.processInfo.environment["XS_FEATURE_\(feature.rawValue.uppercased())"] {
            return override == "1" || override.lowercased() == "true"
        }
        guard let rule = rules[feature.rawValue], rule.enabled else { return false }
        return stableBucket(feature.rawValue) < max(0, min(100, rule.rolloutPercent))
    }

    func refreshIfConfigured() async {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "RolloutConfigURL") as? String,
              let url = URL(string: rawURL), url.scheme == "https" else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return }
            apply(try JSONDecoder().decode(Payload.self, from: data), sourceData: data)
        } catch {
            // Last known valid rules stay active when the config endpoint is unavailable.
        }
    }

    private func restoreCache() {
        guard let data = defaults.data(forKey: cachedPayloadKey), let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        apply(payload, sourceData: nil)
    }

    private func apply(_ payload: Payload, sourceData: Data?) {
        rules.merge(Dictionary(uniqueKeysWithValues: payload.features.map { ($0.key, $0) })) { _, new in new }
        revision = payload.revision
        if let sourceData { defaults.set(sourceData, forKey: cachedPayloadKey) }
    }

    private func stableBucket(_ feature: String) -> Int {
        let identifier: String
        if let value = readInstallationID(), !value.isEmpty {
            identifier = value
        } else if let value = volatileInstallationID, !value.isEmpty {
            identifier = value
        } else {
            let value = UUID().uuidString.lowercased()
            volatileInstallationID = value
            writeInstallationID(value)
            identifier = value
        }
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in "\(identifier)|\(feature)".utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return Int(hash % 100)
    }

    /// The installation bucket is not a credential, but it must remain device
    /// local and stable without putting a durable identifier in UserDefaults.
    /// If Keychain is temporarily unavailable (for example before first
    /// unlock), the in-memory fallback keeps this process deterministic while
    /// avoiding a plaintext persistence downgrade.
    private func readInstallationID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: installationKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    private func writeInstallationID(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: installationKey
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) != errSecSuccess {
            var add = query
            add.merge(attributes) { _, new in new }
            _ = SecItemAdd(add as CFDictionary, nil)
        }
    }
}
