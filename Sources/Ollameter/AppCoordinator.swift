import AppKit

final class AppCoordinator: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let keychain = KeychainStore(service: "dev.ollameter.app", account: "api-key")
    private let client = CloudAPIClient()
    private var apiKey: String?
    private var lastGood: BalanceSnapshot?
    private var lastBalanceError: CloudAPIError?
    private var usageSnapshots: [UsageRange: UsageResponse] = [:]
    private var pollTask: Task<Void, Never>?
    private var hasPromptedKeyMissing = false
    private var hasPromptedAuthError = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        apiKey = keychain.read()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Ollameter")
        item.button?.title = "..."
        statusItem = item
        render()
        startPolling()
        if apiKey == nil, !hasPromptedKeyMissing {
            hasPromptedKeyMissing = true
            presentKeyPrompt()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTask?.cancel()
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runCycle()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func runCycle() async {
        guard let key = apiKey else { render()
            return
        }

        async let balanceResult = withResult { try await self.client.fetchBalance(apiKey: key) }
        async let u24 = withResult { try await self.client.fetchUsage(apiKey: key, range: .h24) }
        async let u7 = withResult { try await self.client.fetchUsage(apiKey: key, range: .d7) }
        async let u30 = withResult { try await self.client.fetchUsage(apiKey: key, range: .d30) }
        let (balance, u24Result, u7Result, u30Result) = await (balanceResult, u24, u7, u30)

        for (range, result) in [(UsageRange.h24, u24Result), (.d7, u7Result), (.d30, u30Result)] {
            if case .success(let response) = result {
                usageSnapshots[range] = response
            }
        }

        switch balance {
        case .success(let snapshot):
            lastGood = snapshot
            lastBalanceError = nil
        case .failure(let error):
            lastBalanceError = error as? CloudAPIError ?? .badResponse
        }
        render()

        if case .failure(let error) = balance,
           let apiError = error as? CloudAPIError,
           case .unauthorized = apiError,
           !hasPromptedAuthError {
            hasPromptedAuthError = true
            DispatchQueue.main.async { [weak self] in
                self?.presentKeyPrompt()
            }
        }
    }

    private func withResult<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func render() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderTitle()
            self.renderMenu()
        }
    }

    private func renderTitle() {
        guard let button = statusItem?.button else { return }

        if apiKey == nil {
            button.attributedTitle = attributedTitle("Set key", color: nil)
            return
        }

        guard let good = lastGood else {
            switch lastBalanceError {
            case .unauthorized:
                button.attributedTitle = attributedTitle("Auth error", color: nil)
            case .transport, .badResponse:
                button.attributedTitle = attributedTitle("Offline", color: nil)
            case .rateLimited:
                button.attributedTitle = attributedTitle("Rate limited", color: nil)
            default:
                button.attributedTitle = attributedTitle("...", color: nil)
            }
            return
        }

        switch lastBalanceError {
        case .unauthorized:
            button.attributedTitle = attributedTitle("Auth error", color: nil)
        case .transport, .badResponse:
            button.attributedTitle = attributedTitle("Offline", color: nil)
        default:
            renderMetric(good, into: button)
        }
    }

    private func renderMetric(_ snapshot: BalanceSnapshot, into button: NSButton) {
        let included = snapshot.included

        if snapshot.isCreditShape, let balance = included.balanceUsd, let allowance = included.allowanceUsd, allowance > 0 {
            let usedPercent = (1 - balance / allowance) * 100
            guard let from = CloudDates.parse(included.period?.from),
                  let until = CloudDates.parse(included.period?.until), until > from else {
                button.attributedTitle = attributedTitle("--", color: nil)
                return
            }
            let now = Date()
            let span = until.timeIntervalSince(from)
            var elapsedPercent = now.timeIntervalSince(from) / span * 100
            elapsedPercent = max(0, min(100, elapsedPercent))
            let (text, color) = Metrics.creditDelta(usedPercent: usedPercent, elapsedPercent: elapsedPercent)
            let nsColor: NSColor? = color == .red ? .systemRed : color == .green ? .systemGreen : nil
            button.attributedTitle = attributedTitle(text, color: nsColor)
            return
        }

        if snapshot.isLegacyShape {
            let sessionRemainder = clampPercent(included.session?.remainingPercent ?? 0)
            let weeklyRemainder = clampPercent(included.weekly?.remainingPercent ?? 0)
            let now = Date()
            let sessionTtl = CloudDates.parse(included.session?.resetsAt)?.timeIntervalSince(now)
            let weeklyTtl = CloudDates.parse(included.weekly?.resetsAt)?.timeIntervalSince(now)
            button.attributedTitle = attributedTitle(
                Metrics.legacySummary(
                    sessionRemainingPercent: sessionRemainder,
                    sessionTtl: sessionTtl,
                    weeklyRemainingPercent: weeklyRemainder,
                    weeklyTtl: weeklyTtl
                ),
                color: nil
            )
            return
        }

        button.attributedTitle = attributedTitle("--", color: nil)
    }

    private func clampPercent(_ value: Double?) -> Double {
        max(0, min(100, value ?? 0))
    }

    private func attributedTitle(_ text: String, color: NSColor?) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        if let color {
            attributes[.foregroundColor] = color
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private func renderMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Ollameter", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if apiKey == nil {
            menu.addItem(disabled("No API key set"))
        } else if lastBalanceError == .unauthorized {
            menu.addItem(disabled("API key rejected"))
        }

        if let good = lastGood, lastBalanceError != .unauthorized {
            let included = good.included
            if good.isCreditShape {
                menu.addItem(disabled("Balance \(formatUsd(included.balanceUsd)) / \(formatUsd(included.allowanceUsd))"))
                if let purchased = good.purchasedUsd {
                    menu.addItem(disabled("Purchased \(formatUsd(purchased))"))
                }
                if let reset = CloudDates.parse(included.period?.until) {
                    menu.addItem(disabled("Resets \(resetDescription(reset))"))
                }
            } else if good.isLegacyShape {
                let now = Date()
                menu.addItem(disabled("Session \(Int(clampPercent(included.session?.remainingPercent ?? 0)))% left, resets \(ttlText(CloudDates.parse(included.session?.resetsAt)?.timeIntervalSince(now), formatter: { Metrics.hHmm($0) }))"))
                menu.addItem(disabled("Weekly \(Int(clampPercent(included.weekly?.remainingPercent ?? 0)))% left, resets \(ttlText(CloudDates.parse(included.weekly?.resetsAt)?.timeIntervalSince(now), formatter: { Metrics.dHh($0) }))"))
                if let purchased = good.purchasedUsd {
                    menu.addItem(disabled("Purchased \(formatUsd(purchased))"))
                }
            } else {
                menu.addItem(disabled("Balance data unavailable"))
            }
            menu.addItem(disabled("Updated \(timeDescription(good.fetchedAt))"))
        } else if lastGood == nil && apiKey != nil {
            switch lastBalanceError {
            case .transport, .badResponse:
                menu.addItem(disabled("Status: Offline"))
            case .rateLimited:
                menu.addItem(disabled("Status: Rate limited"))
            case .unauthorized:
                menu.addItem(disabled("Status: Auth error"))
            default:
                menu.addItem(disabled("Status: Waiting..."))
            }
        }

        menu.addItem(.separator())

        let keyTitle = apiKey == nil ? "Enter API key..." : "Replace API key..."
        let keyItem = NSMenuItem(title: keyTitle, action: #selector(enterKeyPrompt), keyEquivalent: "")
        keyItem.target = self
        menu.addItem(keyItem)

        let quitItem = NSMenuItem(title: "Quit Ollameter", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func disabled(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func formatUsd(_ value: Double?) -> String {
        Metrics.usd(value)
    }

    private func ttlText(_ seconds: TimeInterval?, formatter: (TimeInterval) -> String) -> String {
        guard let seconds, seconds > 0 else { return "--" }
        return formatter(seconds)
    }

    private let resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
        return formatter
    }()

    private func resetDescription(_ date: Date) -> String {
        resetDateFormatter.string(from: date)
    }

    private let updatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func timeDescription(_ date: Date) -> String {
        updatedFormatter.string(from: date)
    }

    private func presentKeyPrompt() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Ollama API key"
        alert.informativeText = "Enter the API key for your ollama.com account. It is stored in your Keychain."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "API key"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try keychain.write(value)
            apiKey = value
            hasPromptedAuthError = false
            render()
            Task { await runCycle() }
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Could not store the key"
            errorAlert.informativeText = "Check that the app has Keychain access."
            errorAlert.runModal()
        }
    }

    @objc private func enterKeyPrompt() {
        presentKeyPrompt()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
