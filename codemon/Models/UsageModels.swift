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

    var credentialsHint: String {
        switch self {
        case .claude: return "Not signed in — run `claude` to log in"
        case .codex: return "Not signed in — run `codex` to log in"
        }
    }

    var expiredHint: String {
        switch self {
        case .claude: return "Credentials expired — run `claude` to log in again"
        case .codex: return "Credentials expired — run `codex` to log in again"
        }
    }

    var hasCredits: Bool {
        switch self {
        case .claude: return true
        case .codex: return false
        }
    }

    var cliName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
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
    var isUnlimited: Bool = false
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
