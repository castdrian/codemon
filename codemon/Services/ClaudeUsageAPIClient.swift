import Foundation

enum UsageAPIError: Error, LocalizedError {
    case unauthorized
    case rateLimited
    case invalidResponse
    case missingOrgId

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired"
        case .rateLimited: return "Rate limited — retrying shortly"
        case .invalidResponse: return "Unexpected response from claude.ai"
        case .missingOrgId: return "Could not determine organization ID"
        }
    }
}

struct ClaudeUsageAPIClient {
    private let session = URLSession(configuration: .ephemeral)

    private func authorizedRequest(path: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com\(path)")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-cli/2.1.0 (external, cli)", forHTTPHeaderField: "User-Agent")
        return request
    }

    func fetchAccount(accessToken: String, planHint: String?) async throws -> AccountInfo {
        let (data, response) = try await session.data(for: authorizedRequest(path: "/api/oauth/profile", accessToken: accessToken))
        try Self.validate(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["account"] as? [String: Any] else {
            throw UsageAPIError.invalidResponse
        }

        let displayName = (account["display_name"] as? String)
            ?? (account["full_name"] as? String)
            ?? (account["email"] as? String)
            ?? "Claude"
        return AccountInfo(displayName: displayName, planLabel: Self.planLabel(account: account, planHint: planHint))
    }

    private static func planLabel(account: [String: Any], planHint: String?) -> String {
        if account["has_claude_max"] as? Bool == true { return "Claude Max" }
        if account["has_claude_pro"] as? Bool == true { return "Claude Pro" }
        guard let planHint, !planHint.isEmpty else { return "Claude" }
        return "Claude \(planHint.capitalized)"
    }

    func fetchUsage(accessToken: String) async throws -> UsageSnapshot {
        let (data, response) = try await session.data(for: authorizedRequest(path: "/api/oauth/usage", accessToken: accessToken))
        try Self.validate(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAPIError.invalidResponse
        }
        return Self.parse(json)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageAPIError.unauthorized
        }
        if http.statusCode == 429 {
            throw UsageAPIError.rateLimited
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UsageAPIError.invalidResponse
        }
    }

    private static func parse(_ json: [String: Any]) -> UsageSnapshot {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func number(_ any: Any?) -> Double? {
            if let d = any as? Double { return d }
            if let i = any as? Int { return Double(i) }
            return nil
        }

        func window(_ key: String) -> UsageWindow? {
            guard let entry = json[key] as? [String: Any],
                  let utilization = number(entry["utilization"]) else { return nil }
            let resetsAt = (entry["resets_at"] as? String).flatMap { formatter.date(from: $0) }
            return UsageWindow(utilization: utilization, resetsAt: resetsAt)
        }

        let session = window("five_hour")
        let weekly = window("seven_day")
        let credit = parseCredit(json, numberParser: number)

        return UsageSnapshot(session: session, weekly: weekly, credit: credit, fetchedAt: Date())
    }

    private static func parseCredit(_ json: [String: Any], numberParser number: (Any?) -> Double?) -> CreditUsage? {
        guard let entry = json["extra_usage"] as? [String: Any] else { return nil }

        let used = number(entry["used_credits"])
        let limit = number(entry["monthly_limit"])
        let currency = entry["currency"] as? String
        let decimalPlaces = (entry["decimal_places"] as? Int) ?? 2

        guard entry["is_enabled"] as? Bool == true else { return nil }
        guard used != nil || limit != nil else { return nil }

        if limit == nil, let balance = spendBalance(json, numberParser: number) {
            let spent = used ?? 0
            let total = spent + balance
            return CreditUsage(
                remaining: balance,
                limit: nil,
                used: used,
                percentUsed: total > 0 ? (spent / total) * 100 : 0,
                currency: currency,
                decimalPlaces: decimalPlaces
            )
        }

        return CreditUsage(
            remaining: limit.flatMap { l in used.map { l - $0 } },
            limit: limit,
            used: used,
            percentUsed: number(entry["utilization"]),
            currency: currency,
            decimalPlaces: decimalPlaces
        )
    }

    private static func spendBalance(_ json: [String: Any], numberParser number: (Any?) -> Double?) -> Double? {
        guard let spend = json["spend"] as? [String: Any] else { return nil }
        if let balance = spend["balance"] as? [String: Any] {
            return number(balance["amount_minor"])
        }
        return number(spend["balance"])
    }
}
