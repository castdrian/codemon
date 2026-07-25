import Foundation

struct CodexUsageAPIClient {
    private let session = URLSession(configuration: .ephemeral)

    func fetchUsage(cookieHeader: String) async throws -> (snapshot: UsageSnapshot, account: AccountInfo) {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codemon", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAPIError.invalidResponse
        }

        let rateLimit = (json["rate_limit"] as? [String: Any]) ?? json
        let session = usageWindow(rateLimit["primary_window"] as? [String: Any])
        let weekly = usageWindow(rateLimit["secondary_window"] as? [String: Any])
        guard session != nil || weekly != nil else { throw UsageAPIError.invalidResponse }

        let planType = (json["plan_type"] as? String) ?? (rateLimit["plan_type"] as? String)
        let planLabel = planType.map(Self.planLabel) ?? "Codex"
        let displayName = (json["account_name"] as? String) ?? "Codex"
        return (UsageSnapshot(session: session, weekly: weekly, credit: nil, fetchedAt: Date()), AccountInfo(displayName: displayName, planLabel: planLabel))
    }

    private func usageWindow(_ entry: [String: Any]?) -> UsageWindow? {
        guard let entry, let usedPercent = number(entry["used_percent"]) else { return nil }
        let reset = number(entry["reset_at"]).map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(utilization: usedPercent, resetsAt: reset)
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw UsageAPIError.invalidResponse }
        if response.statusCode == 401 || response.statusCode == 403 { throw UsageAPIError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw UsageAPIError.invalidResponse }
    }

    private static func planLabel(_ planType: String) -> String {
        let normalized = planType.replacingOccurrences(of: "_", with: " ").capitalized
        return "Codex \(normalized)"
    }
}
