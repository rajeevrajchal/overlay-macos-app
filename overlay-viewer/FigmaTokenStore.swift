import Foundation
import Security

/// Tokens returned by Figma's OAuth2 token/refresh endpoints, with the
/// access token's absolute expiry computed at save time so callers never
/// have to re-derive it from `expires_in`.
struct FigmaTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool {
        // 60s skew so we refresh slightly before Figma actually rejects the token.
        Date() > expiresAt.addingTimeInterval(-60)
    }
}

protocol FigmaTokenStoring {
    func save(_ tokens: FigmaTokens)
    func load() -> FigmaTokens?
    func clear()
}

/// Persists Figma OAuth tokens in the macOS Keychain, scoped to this app.
/// Sandboxed apps need an explicit `keychain-access-groups` entitlement
/// (see overlay-viewer.entitlements) — without one, SecItemAdd fails with
/// errSecMissingEntitlement and writes silently go nowhere, which looks
/// exactly like "Connect Figma" working until the app is relaunched.
final class FigmaKeychainTokenStore: FigmaTokenStoring {

    private let service = "np.com.rajeevrajchal.overlay-viewer.figma-oauth"
    private let account = "figma-tokens"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func save(_ tokens: FigmaTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else {
            NSLog("FigmaKeychainTokenStore: failed to encode tokens")
            return
        }
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("FigmaKeychainTokenStore: failed to save tokens (OSStatus \(status))")
        }
    }

    func load() -> FigmaTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecSuccess && status != errSecItemNotFound {
                NSLog("FigmaKeychainTokenStore: failed to load tokens (OSStatus \(status))")
            }
            return nil
        }
        do {
            return try JSONDecoder().decode(FigmaTokens.self, from: data)
        } catch {
            NSLog("FigmaKeychainTokenStore: failed to decode stored tokens")
            return nil
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
