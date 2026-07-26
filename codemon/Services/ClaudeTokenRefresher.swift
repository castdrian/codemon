import Foundation

struct RefreshedTokens {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
}

enum ClaudeTokenRefresher {
    private static let endpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    static func exchange(refreshToken: String) async throws -> RefreshedTokens {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-cli/2.1.0 (external, cli)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ])

        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard let http = response as? HTTPURLResponse,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode), let accessToken = json["access_token"] as? String else {
            throw mapFailure(statusCode: http.statusCode, json: json)
        }

        return RefreshedTokens(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            expiresAt: seconds(json["expires_in"]).map { Date().addingTimeInterval($0) }
        )
    }

    private static func mapFailure(statusCode: Int, json: [String: Any]) -> UsageAPIError {
        if json["error"] as? String == "invalid_grant" { return .unauthorized }
        if statusCode == 401 || statusCode == 403 { return .unauthorized }
        if statusCode == 429 { return .rateLimited }
        return .invalidResponse
    }

    private static func seconds(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}
