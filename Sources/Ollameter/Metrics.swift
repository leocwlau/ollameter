import Foundation

enum MetricColor {
    case red
    case green
    case neutral
}

enum Metrics {
    static func creditDelta(usedPercent: Double, elapsedPercent: Double) -> (text: String, color: MetricColor) {
        let raw = usedPercent - elapsedPercent
        let rounded = Int(raw.rounded(.toNearestOrAwayFromZero))
        let color: MetricColor = raw > 0 ? .red : .green
        let text: String
        switch rounded {
        case ..<0:
            text = "\(rounded)%"
        case 0:
            text = "0%"
        default:
            text = "+\(rounded)%"
        }
        return (text, color)
    }

    static func legacySummary(sessionRemainingPercent: Double,
                              sessionTtl: TimeInterval?,
                              weeklyRemainingPercent: Double,
                              weeklyTtl: TimeInterval?) -> String {
        "S \(Int(sessionRemainingPercent.rounded()))% \(ttlText(sessionTtl, formatter: hHmm))"
        + " W \(Int(weeklyRemainingPercent.rounded()))% \(ttlText(weeklyTtl, formatter: dHh))"
    }

    static func hHmm(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return "\(total / 3600):\(String(format: "%02d", (total % 3600) / 60))"
    }

    static func dHh(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return "\(total / 86400)d:\((total % 86400) / 3600)h"
    }

    static func usd(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "$%.2f", value)
    }

    private static func ttlText(_ seconds: TimeInterval?, formatter: (TimeInterval) -> String) -> String {
        guard let seconds, seconds > 0 else { return "--" }
        return formatter(seconds)
    }
}
