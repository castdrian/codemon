import Foundation

enum UsageProvider: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    var loginURL: URL {
        switch self {
        case .claude: return URL(string: "https://claude.ai/login")!
        case .codex: return URL(string: "https://chatgpt.com/auth/login?next=/codex/settings/usage")!
        }
    }

    var cookieDomains: [String] {
        switch self {
        case .claude: return ["claude.ai"]
        case .codex: return ["chatgpt.com"]
        }
    }

    var desktopBundleIdentifiers: Set<String> {
        switch self {
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .codex: return ["com.openai.codex"]
        }
    }
}

struct UsageWindow: Equatable {
    var utilization: Double
    var resetsAt: Date?
}

struct CreditUsage: Equatable {
    var remaining: Double?
    var limit: Double?
    var used: Double?
    var percentUsed: Double?
    var currency: String?
    var decimalPlaces: Int
}

struct UsageSnapshot: Equatable {
    var session: UsageWindow?
    var weekly: UsageWindow?
    var credit: CreditUsage?
    var fetchedAt: Date
}

struct AccountInfo: Equatable, Codable {
    var displayName: String
    var planLabel: String
}

enum AuthState: Equatable {
    case signedOut
    case signedIn
    case expired
}
