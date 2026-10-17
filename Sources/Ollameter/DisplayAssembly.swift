import Foundation

struct ModelUsage: Hashable {
    var name: String
    var requestCount: Int?
    var usageUsd: Double?
}

struct LimitBar: Hashable {
    var label: String
    var usedPercent: Double
    var fillColor: MetricColor
    var resetText: String?
}

struct CreditDisplay {
    var deltaText: String
    var deltaColor: MetricColor
    var deltaCaption: String
    var balanceText: String
    var allowanceText: String
    var resetsText: String?
    var purchasedText: String?
    var usedPercent: Double
    var usedColor: MetricColor
    var elapsedPercent: Double
}

struct LegacyDisplay {
    var sessionBar: LimitBar
    var weeklyBar: LimitBar
    var purchasedText: String?
}

struct HistoryRow: Hashable {
    var label: String
    var isTotal: Bool
    var isPartial: Bool
    var requestCount: Int?
    var usageUsd: Double?
}

struct HistoryDisplay {
    var rows: [HistoryRow]
    var hasUsdData: Bool
    var isAvailable: Bool
}

enum DashboardData {
    case credit(CreditDisplay)
    case legacy(LegacyDisplay)
}

enum DisplayAssembly {
    static func clampPercentage(_ value: Double) -> Double {
        max(0, min(100, value))
    }

    // MARK: FR-6 (credit-based plans)

    static func credit(_ snapshot: BalanceSnapshot,
                       usageResponses: [UsageRange: UsageResponse],
                       selectedRange: UsageRange,
                       now: Date) -> CreditDisplay? {
        let included = snapshot.included
        guard let balanceUsd = included.balanceUsd,
              let allowanceUsd = included.allowanceUsd,
              allowanceUsd > 0 else { return nil }
        guard let from = CloudDates.parse(included.period?.from),
              let until = CloudDates.parse(included.period?.until),
              until > from else { return nil }

        let usedPercent = clampPercentage((1 - balanceUsd / allowanceUsd) * 100)
        let span = until.timeIntervalSince(from)
        let elapsedPercent = clampPercentage(now.timeIntervalSince(from) / span * 100)
        let delta = Metrics.creditDelta(usedPercent: usedPercent, elapsedPercent: elapsedPercent)

        return CreditDisplay(
            deltaText: delta.text,
            deltaColor: delta.color,
            deltaCaption: delta.color == .red ? "ahead of usage pace" : "under usage pace",
            balanceText: Metrics.usd(balanceUsd),
            allowanceText: Metrics.usd(allowanceUsd),
            resetsText: momentText(until),
            purchasedText: snapshot.purchasedUsd.map { Metrics.usd($0) },
            usedPercent: usedPercent,
            usedColor: delta.color,
            elapsedPercent: elapsedPercent
        )
    }

    // MARK: FR-7 (legacy plans)

    static func legacy(_ snapshot: BalanceSnapshot, now: Date) -> LegacyDisplay? {
        guard let session = snapshot.included.session, let weekly = snapshot.included.weekly else { return nil }
        let sessionBar = limitBar(
            label: "Session",
            remainingPercent: clampPercentage(session.remainingPercent ?? 0),
            resetAt: CloudDates.parse(session.resetsAt),
            window: 5 * 3600,
            formatter: Metrics.hHmm,
            now: now
        )
        let weeklyBar = limitBar(
            label: "Weekly",
            remainingPercent: clampPercentage(weekly.remainingPercent ?? 0),
            resetAt: CloudDates.parse(weekly.resetsAt),
            window: 7 * 86400,
            formatter: Metrics.dHh,
            now: now
        )
        return LegacyDisplay(
            sessionBar: sessionBar,
            weeklyBar: weeklyBar,
            purchasedText: snapshot.purchasedUsd.map { Metrics.usd($0) }
        )
    }

    static func limitBar(label: String,
                         remainingPercent: Double,
                         resetAt: Date?,
                         window: TimeInterval,
                         formatter: (TimeInterval) -> String,
                         now: Date) -> LimitBar {
        let usedPercent = clampPercentage(100 - remainingPercent)
        var fillColor: MetricColor = .neutral
        if let resetAt, resetAt > now, resetAt.timeIntervalSince(now) <= window {
            let ttl = resetAt.timeIntervalSince(now)
            let elapsedPercent = clampPercentage((window - ttl) / window * 100)
            fillColor = usedPercent <= elapsedPercent ? .green : .red
        }
        var resetText: String?
        if let resetAt {
            let ttl = resetAt.timeIntervalSince(now)
            if ttl > 0 {
                resetText = formatter(ttl)
            }
        }
        return LimitBar(label: label, usedPercent: usedPercent, fillColor: fillColor, resetText: resetText)
    }

    // MARK: FR-6/FR-7 model list

    static func models(for responses: [UsageRange: UsageResponse], range: UsageRange) -> [ModelUsage] {
        guard let response = responses[range] else { return [] }
        let groups = response.totals?.groups
            ?? (response.buckets ?? []).flatMap { $0.groups ?? [] }
        return groups.compactMap { group -> ModelUsage? in
            guard let name = group.model ?? group.name, !name.isEmpty else { return nil }
            return ModelUsage(
                name: name,
                requestCount: group.requestCount,
                usageUsd: group.usageUsd
            )
        }
        .sorted { ($0.requestCount ?? -1) > ($1.requestCount ?? -1) }
    }

    // MARK: FR-8 (usage history list)

    static func history(for range: UsageRange, responses: [UsageRange: UsageResponse]) -> HistoryDisplay {
        guard let response = responses[range] else {
            return HistoryDisplay(rows: [], hasUsdData: false, isAvailable: false)
        }
        var rows: [HistoryRow] = []
        if let totals = response.totals {
            rows.append(HistoryRow(
                label: "Total",
                isTotal: true,
                isPartial: false,
                requestCount: totals.requestCount,
                usageUsd: totals.usageUsd
            ))
        }
        for bucket in response.buckets ?? [] {
            rows.append(HistoryRow(
                label: bucketLabel(from: bucket.from, until: bucket.until),
                isTotal: false,
                isPartial: bucket.partial ?? false,
                requestCount: bucket.requestCount,
                usageUsd: bucket.usageUsd
            ))
        }
        return HistoryDisplay(
            rows: rows,
            hasUsdData: rows.contains { $0.usageUsd != nil },
            isAvailable: true
        )
    }

    static func bucketLabel(from: String?, until: String?) -> String {
        guard let fromDate = CloudDates.parse(from) else { return "..." }
        let startText = momentFormatter.string(from: fromDate)
        guard let untilDate = CloudDates.parse(until) else { return startText }
        if Calendar.current.isDate(untilDate, inSameDayAs: fromDate) {
            return "\(startText) - \(timeFormatter.string(from: untilDate))"
        }
        return "\(startText) - \(momentFormatter.string(from: untilDate))"
    }

    static func momentText(_ date: Date) -> String {
        momentFormatter.string(from: date)
    }

    private static let momentFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter
    }()
}
