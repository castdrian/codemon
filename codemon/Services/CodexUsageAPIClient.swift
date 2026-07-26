import Foundation

struct CodexUsageAPIClient {
    private let session = URLSession(configuration: .ephemeral)
    private static let sessionWindowCutoff: Double = 6 * 60 * 60

    func fetchUsage(accessToken: String, accountId: String?, accountName: String?) async throws -> (snapshot: UsageSnapshot, account: AccountInfo) {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codemon", forHTTPHeaderField: "User-Agent")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        try validate(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAPIError.invalidResponse
        }

        let rateLimit = (json["rate_limit"] as? [String: Any]) ?? [:]
        let windows = [rateLimit["primary_window"], rateLimit["secondary_window"]]
            .compactMap { usageWindow($0 as? [String: Any]) }

        let session = windows.first { $0.isSession }?.window
        let weekly = windows.first { !$0.isSession }?.window
        let credit = creditUsage(json["credits"] as? [String: Any])
        guard session != nil || weekly != nil || credit != nil else { throw UsageAPIError.invalidResponse }

        let planType = (json["plan_type"] as? String) ?? (rateLimit["plan_type"] as? String)
        let planLabel = planType.map(Self.planLabel) ?? "Codex"
        let displayName = accountName
            ?? (json["account_name"] as? String)
            ?? (json["email"] as? String)
            ?? "Codex"
        return (
            UsageSnapshot(session: session, weekly: weekly, credit: credit, fetchedAt: Date()),
            AccountInfo(displayName: displayName, planLabel: planLabel)
        )
    }

    private func usageWindow(_ entry: [String: Any]?) -> (window: UsageWindow, isSession: Bool)? {
        guard let entry, let usedPercent = number(entry["used_percent"]) else { return nil }
        let reset = number(entry["reset_at"]).map { Date(timeIntervalSince1970: $0) }
        let windowSeconds = number(entry["limit_window_seconds"]) ?? Self.sessionWindowCutoff
        let utilization = min(max(usedPercent, 0), 100)
        return (
            UsageWindow(utilization: utilization, resetsAt: reset),
            windowSeconds <= Self.sessionWindowCutoff
        )
    }

    private func creditUsage(_ entry: [String: Any]?) -> CreditUsage? {
        guard let entry else { return nil }
        let unlimited = entry["unlimited"] as? Bool ?? false
        if unlimited {
            return CreditUsage(remaining: nil, limit: nil, used: nil, percentUsed: nil, currency: nil, decimalPlaces: 0, isUnlimited: true, displayUnit: .credits)
        }

        guard entry["has_credits"] as? Bool == true,
              let balance = number(entry["balance"]),
              balance > 0,
              let baseline = CreditBaselineStore.reconcile(balance: balance, for: .codex) else {
            _ = CreditBaselineStore.reconcile(balance: 0, for: .codex)
            return nil
        }

        let spent = max(baseline - balance, 0)
        return CreditUsage(
            remaining: balance,
            limit: baseline,
            used: spent,
            percentUsed: min(max(spent / baseline * 100, 0), 100),
            currency: nil,
            decimalPlaces: 0,
            isUnlimited: false,
            displayUnit: .credits
        )
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
        if response.statusCode == 429 { throw UsageAPIError.rateLimited }
        guard (200..<300).contains(response.statusCode) else { throw UsageAPIError.invalidResponse }
    }

    private static func planLabel(_ planType: String) -> String {
        let normalized = planType.replacingOccurrences(of: "_", with: " ").capitalized
        return "Codex \(normalized)"
    }
}
