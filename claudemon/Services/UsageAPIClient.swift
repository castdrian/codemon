import Foundation

enum UsageAPIError: Error, LocalizedError {
    case unauthorized
    case invalidResponse
    case missingOrgId

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired"
        case .invalidResponse: return "Unexpected response from claude.ai"
        case .missingOrgId: return "Could not determine organization ID"
        }
    }
}

struct UsageAPIClient {
    private let session = URLSession(configuration: .ephemeral)

    func fetchBootstrap(cookieHeader: String) async throws -> (orgId: String, account: AccountInfo) {
        var request = URLRequest(url: URL(string: "https://claude.ai/api/bootstrap")!)
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let account = json["account"] as? [String: Any],
            let memberships = account["memberships"] as? [[String: Any]],
            let membership = memberships.first,
            let organization = membership["organization"] as? [String: Any],
            let orgId = organization["uuid"] as? String
        else {
            throw UsageAPIError.missingOrgId
        }

        KeychainStore.save(orgId, account: "orgId")

        let displayName = (account["display_name"] as? String)
            ?? (account["full_name"] as? String)
            ?? "Claude"
        let capabilities = organization["capabilities"] as? [String] ?? []
        let planLabel = Self.planLabel(capabilities: capabilities)

        return (orgId, AccountInfo(displayName: displayName, planLabel: planLabel))
    }

    private static func planLabel(capabilities: [String]) -> String {
        let ranked: [(String, String)] = [
            ("claude_enterprise", "Claude Enterprise"),
            ("claude_team", "Claude Team"),
            ("claude_max", "Claude Max"),
            ("claude_pro", "Claude Pro")
        ]
        for (capability, label) in ranked where capabilities.contains(capability) {
            return label
        }
        return "Claude Free"
    }

    func fetchUsage(cookieHeader: String, orgId: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://claude.ai/api/organizations/\(orgId)/usage")!)
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAPIError.invalidResponse
        }

        var snapshot = Self.parse(json)

        if let credit = snapshot.credit, credit.limit == nil,
           let balance = try? await fetchPrepaidBalance(cookieHeader: cookieHeader, orgId: orgId) {
            let used = credit.used ?? 0
            let total = used + balance
            snapshot.credit?.remaining = balance
            snapshot.credit?.percentUsed = total > 0 ? (used / total) * 100 : 0
        }

        return snapshot
    }

    private func fetchPrepaidBalance(cookieHeader: String, orgId: String) async throws -> Double? {
        var request = URLRequest(url: URL(string: "https://claude.ai/api/organizations/\(orgId)/prepaid/credits")!)
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let amount = json["amount"] as? Double { return amount }
        if let amount = json["amount"] as? Int { return Double(amount) }
        return nil
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageAPIError.unauthorized
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
        guard let entry = json["extra_usage"] as? [String: Any],
              entry["is_enabled"] as? Bool == true else { return nil }

        let used = number(entry["used_credits"])
        let limit = number(entry["monthly_limit"])
        guard used != nil || limit != nil else { return nil }

        let percent = number(entry["utilization"])
        let remaining = limit.flatMap { l in used.map { l - $0 } }
        let currency = entry["currency"] as? String
        let decimalPlaces = (entry["decimal_places"] as? Int) ?? 2

        return CreditUsage(
            remaining: remaining,
            limit: limit,
            used: used,
            percentUsed: percent,
            currency: currency,
            decimalPlaces: decimalPlaces
        )
    }
}
