import SwiftUI

struct FloatingWidgetView: View {
    @ObservedObject var providerStore: ProviderUsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            usageRow(title: "Session", window: providerStore.snapshot?.session)
            usageRow(title: "Weekly", window: providerStore.snapshot?.weekly)
            if providerStore.provider == .claude {
                creditRow(providerStore.snapshot?.credit)
            }
        }
        .padding(14)
        .frame(width: 216, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(providerStore.accountInfo?.displayName ?? providerStore.provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("· \(providerStore.accountInfo?.planLabel ?? "Not signed in")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Divider()
        }
    }

    @ViewBuilder
    private func usageRow(title: String, window: UsageWindow?) -> some View {
        let value = window?.utilization
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text(value.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.primary)

            UsageBar(percent: value ?? 0, color: Self.usageColor(for: value ?? 0))

            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Self.resetLabel(window?.resetsAt, now: context.date))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func creditRow(_ credit: CreditUsage?) -> some View {
        let percent = credit?.percentUsed
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Credits")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text(Self.creditValueLabel(credit))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.primary)

            UsageBar(percent: percent ?? 0, color: Self.usageColor(for: percent ?? 0))

            Text(" ")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private static func creditValueLabel(_ credit: CreditUsage?) -> String {
        guard let credit else { return "—" }
        if let remaining = credit.remaining {
            return "\(formatCurrency(remaining, credit: credit)) left"
        }
        if let percent = credit.percentUsed {
            return "\(Int(percent.rounded()))%"
        }
        return "—"
    }

    private static func formatCurrency(_ minorUnits: Double, credit: CreditUsage) -> String {
        let value = minorUnits / pow(10, Double(credit.decimalPlaces))
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        if let currency = credit.currency {
            formatter.currencyCode = currency
        }
        formatter.minimumFractionDigits = credit.decimalPlaces
        formatter.maximumFractionDigits = credit.decimalPlaces
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private static func resetLabel(_ resetsAt: Date?, now: Date) -> String {
        guard let resetsAt else { return " " }
        let interval = resetsAt.timeIntervalSince(now)
        guard interval > 0 else { return "resetting…" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        if minutes > 0 { return "resets in \(minutes)m" }
        return "resets in \(Int(interval))s"
    }

    private static func usageColor(for percent: Double) -> Color {
        switch percent {
        case ..<70: return Color(red: 0.204, green: 0.478, blue: 0.965)
        case ..<90: return Color(red: 0.988, green: 0.749, blue: 0.176)
        default: return Color(red: 0.910, green: 0.298, blue: 0.235)
        }
    }
}

/// `ProgressView(.linear)` ignores `.tint()` on macOS and always renders the
/// system gray track, so the fill is drawn manually here instead.
private struct UsageBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(percent, 0), 100) / 100)
            }
        }
        .frame(height: 5)
    }
}
