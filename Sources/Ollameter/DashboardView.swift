import AppKit
import SwiftUI

struct Banner: Equatable {
    enum Style: Equatable { case error, warning, info }
    var style: Style
    var text: String
}

final class PopoverViewModel: ObservableObject {
    @Published var data: DashboardData?
    @Published var banner: Banner?
    @Published var usageResponses: [UsageRange: UsageResponse] = [:]
    @Published var selectedRange: UsageRange = .h24
    @Published var updatedAt: Date?
    @Published var showKeyForm = false
    @Published var hasStoredKey = false
    @Published var keyDraft = ""

    var onKeyEntered: ((String) -> Void)?

    var modelUsages: [ModelUsage] {
        DisplayAssembly.models(for: usageResponses, range: selectedRange)
    }

    func commitKey() {
        let value = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onKeyEntered?(value)
        keyDraft = ""
    }
}

struct DashboardView: View {
    @ObservedObject var model: PopoverViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let banner = model.banner {
                BannerView(banner: banner)
            }

            if model.showKeyForm {
                KeyEntryForm(model: model)
            } else if let data = model.data {
                DataView(model: model, data: data, usages: model.modelUsages)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Fetching balance...").font(.caption).foregroundStyle(.secondary)
                }
            }

            FooterView(model: model)
        }
        .padding(12)
        .frame(width: 320)
    }
}

struct BannerView: View {
    var banner: Banner

    var body: some View {
        HStack(spacing: 6) {
            Text(banner.text).font(.caption)
            Spacer()
        }
        .padding(8)
        .background(bannerBackground.opacity(0.15))
        .foregroundColor(bannerText)
        .cornerRadius(6)
    }

    private var colorSystem: NSColor {
        switch banner.style {
        case .error: return .systemRed
        case .warning: return .systemOrange
        case .info: return .systemBlue
        }
    }

    private var bannerBackground: Color { Color(nsColor: colorSystem) }
    private var bannerText: Color { Color(nsColor: colorSystem) }
}

struct KeyEntryForm: View {
    @ObservedObject var model: PopoverViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ollama API key").font(.headline)
            SecureField("API key", text: $model.keyDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.commitKey() }
            Text("Stored in your Keychain. Create one at ollama.com.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                if model.hasStoredKey {
                    Button("Cancel") { model.showKeyForm = false }
                        .keyboardShortcut(.cancelAction)
                }
                Button("Save") { model.commitKey() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct DataView: View {
    @ObservedObject var model: PopoverViewModel
    var data: DashboardData
    var usages: [ModelUsage]

    var body: some View {
        switch data {
        case .credit(let credit):
            CreditDataView(model: model, credit: credit, usages: usages)
        case .legacy(let legacy):
            LegacyDataView(model: model, legacy: legacy, usages: usages)
        }
    }
}

struct CreditDataView: View {
    @ObservedObject var model: PopoverViewModel
    var credit: CreditDisplay
    var usages: [ModelUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(credit.deltaText)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundColor(color(credit.deltaColor))
                Text(credit.deltaCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LimitBarView(
                label: "Usage",
                fillFraction: credit.usedPercent / 100,
                fillColor: color(credit.usedColor),
                caption: "\(credit.usageText) of \(credit.allowanceText) used - \(percent(credit.usedPercent))"
            )
            LimitBarView(
                label: "Period",
                fillFraction: credit.elapsedPercent / 100,
                fillColor: color(.green),
                caption: "\(percent(credit.elapsedPercent)) of period passed"
            )

            keyValue("Balance", "\(credit.balanceText) / \(credit.allowanceText)")
            if let purchased = credit.purchasedText {
                keyValue("Purchased", purchased)
            }
            if let resets = credit.resetsText {
                keyValue("Resets", resets)
            }

            ModelUsageRangeSwitcher(model: model)
            ModelUsageList(models: usages)
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.medium)
        }
    }
}

struct LegacyDataView: View {
    @ObservedObject var model: PopoverViewModel
    var legacy: LegacyDisplay
    var usages: [ModelUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LimitBarView(
                label: "Session",
                fillFraction: legacy.sessionBar.usedPercent / 100,
                fillColor: color(legacy.sessionBar.fillColor),
                caption: barCaption(legacy.sessionBar)
            )
            LimitBarView(
                label: "Weekly",
                fillFraction: legacy.weeklyBar.usedPercent / 100,
                fillColor: color(legacy.weeklyBar.fillColor),
                caption: barCaption(legacy.weeklyBar)
            )

            if let purchased = legacy.purchasedText {
                HStack {
                    Text("Purchased").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(purchased).font(.caption).fontWeight(.medium)
                }
            }

            ModelUsageRangeSwitcher(model: model)
            ModelUsageList(models: usages)
        }
    }

    private func barCaption(_ bar: LimitBar) -> String {
        var parts = ["\(Int(bar.usedPercent.rounded()))% used"]
        if let reset = bar.resetText {
            parts.append("resets in \(reset)")
        }
        return parts.joined(separator: " - ")
    }
}

struct LimitBarView: View {
    var label: String
    var fillFraction: Double
    var fillColor: Color
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(nsColor: .systemBlue).opacity(0.3))
                    Capsule().fill(fillColor).frame(width: max(0, geometry.size.width * fillFraction))
                }
            }
            .frame(height: 8)
        }
    }
}

struct ModelUsageList: View {
    var models: [ModelUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model usage").font(.caption).foregroundStyle(.secondary)
            if models.isEmpty {
                Text("No model activity recorded yet").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(models, id: \.self) { usage in
                    HStack(spacing: 8) {
                        Text(usage.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(summary(usage)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }

    private func summary(_ usage: ModelUsage) -> String {
        var parts: [String] = []
        if let count = usage.requestCount {
            parts.append("\(count) req")
        }
        if let usd = usage.usageUsd {
            parts.append(String(format: "$%.2f", usd))
        }
        return parts.isEmpty ? "..." : parts.joined(separator: " - ")
    }
}

struct ModelUsageRangeSwitcher: View {
    @ObservedObject var model: PopoverViewModel

    var body: some View {
        Picker("Model usage range", selection: $model.selectedRange) {
            Text("24h").tag(UsageRange.h24)
            Text("7d").tag(UsageRange.d7)
            Text("30d").tag(UsageRange.d30)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct FooterView: View {
    @ObservedObject var model: PopoverViewModel
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter
    }()

    var body: some View {
        HStack {
            if let updatedAt = model.updatedAt {
                Text("Updated " + Self.timeFormatter.string(from: updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.hasStoredKey {
                Button("Replace key...") { model.showKeyForm = true }
                    .controlSize(.small)
            }
            Button("Quit Ollameter") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
        }
    }
}

func color(_ metric: MetricColor) -> Color {
    switch metric {
    case .red: return Color(nsColor: .systemRed)
    case .green: return Color(nsColor: .systemGreen)
    case .neutral: return Color(nsColor: .systemGray)
    }
}
