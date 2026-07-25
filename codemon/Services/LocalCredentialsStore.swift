import Foundation
import Security

struct ProviderCredentials: Sendable {
    var accessToken: String
    var accountId: String?
    var planHint: String?
    var accountName: String?
    var expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

enum CredentialsError: LocalizedError {
    case missing(UsageProvider)
    case unreadable(UsageProvider)

    var errorDescription: String? {
        switch self {
        case .missing(let provider), .unreadable(let provider):
            return provider.credentialsHint
        }
    }
}

enum LocalCredentialsStore {
    static func load(for provider: UsageProvider) throws -> ProviderCredentials {
        switch provider {
        case .claude: return try loadClaude()
        case .codex: return try loadCodex()
        }
    }

    private static func loadClaude() throws -> ProviderCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            throw CredentialsError.missing(.claude)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              !accessToken.isEmpty else {
            throw CredentialsError.unreadable(.claude)
        }

        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return ProviderCredentials(
            accessToken: accessToken,
            accountId: json["organizationUuid"] as? String,
            planHint: oauth["subscriptionType"] as? String,
            expiresAt: expiresAt
        )
    }

    private static func loadCodex() throws -> ProviderCredentials {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url) else {
            throw CredentialsError.missing(.codex)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialsError.unreadable(.codex)
        }

        if let tokens = json["tokens"] as? [String: Any],
           let accessToken = tokens["access_token"] as? String,
           !accessToken.isEmpty {
            return ProviderCredentials(
                accessToken: accessToken,
                accountId: tokens["account_id"] as? String,
                planHint: nil,
                accountName: (tokens["id_token"] as? String).flatMap(Self.name(fromIDToken:)),
                expiresAt: nil
            )
        }

        if let apiKey = json["OPENAI_API_KEY"] as? String, !apiKey.isEmpty {
            return ProviderCredentials(accessToken: apiKey, accountId: nil, planHint: nil, accountName: nil, expiresAt: nil)
        }

        throw CredentialsError.unreadable(.codex)
    }

    private static func name(fromIDToken token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return nil }

        var encoded = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)

        guard let data = Data(base64Encoded: encoded),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = claims["name"] as? String,
              !name.isEmpty else { return nil }
        return name
    }
}
