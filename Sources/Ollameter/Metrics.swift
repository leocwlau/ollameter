import Foundation

enum MetricColor {
    case red
    case green
    case neutral
}

enum Metrics {
    static func creditDelta(usedPercent: Double, elapsedPercent: Double) -> (text: String, color: MetricColor) {
        let raw = usedPercent - elapsedPercent
        let color: MetricColor = raw > 0 ? .red : .green
        return (percentText(raw, signed: true), color)
    }

    static func legacySummary(sessionRemainingPercent: Double,
                              sessionTtl: TimeInterval?,
                              weeklyRemainingPercent: Double,
                              weeklyTtl: TimeInterval?) -> String {
        "S \(percentText(sessionRemainingPercent)) \(ttlText(sessionTtl, formatter: hHmm))"
        + " W \(percentText(weeklyRemainingPercent)) \(ttlText(weeklyTtl, formatter: dHh))"
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

    private static func percentText(_ value: Double, signed: Bool = false) -> String {
        let formatted = String(format: "%.1f", value)
        if signed, value > 0 {
            return "+\(formatted)%"
        }
        if signed, value < 0 {
            return "\(formatted)%"
        }
        if signed {
            return "0.0%"
        }
        return "\(formatted)%"
    }

    private static func ttlText(_ seconds: TimeInterval?, formatter: (TimeInterval) -> String) -> String {
        guard let seconds, seconds > 0 else { return "--" }
        return formatter(seconds)
    }
}
