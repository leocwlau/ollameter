import AppKit
import SwiftUI

final class AppCoordinator: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let keychain = KeychainStore(service: "dev.ollameter.app", account: "api-key")
    private let client = CloudAPIClient()
    private var apiKey: String?
    private var lastGood: BalanceSnapshot?
    private var lastBalanceError: CloudAPIError?
    private var usageResponses: [UsageRange: UsageResponse] = [:]
    private var pollTask: Task<Void, Never>?
    private var lastCloseDate: Date?
    private var mouseDownMonitor: Any?

    private lazy var viewModel = makeViewModel()
    private lazy var popover: NSPopover = makePopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        apiKey = keychain.read()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = menuBarIcon()
            ?? NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Ollameter")
        item.button?.attributedTitle = plainTitle("...")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
        render()
        startPolling()
        installOutsideClickMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTask?.cancel()
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runCycle()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func installOutsideClickMonitor() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    private func runCycle() async {
        guard let key = apiKey else {
            render()
            return
        }

        async let balanceResult = withResult { try await self.client.fetchBalance(apiKey: key) }
        async let u24 = withResult { try await self.client.fetchUsage(apiKey: key, range: .h24) }
        async let u7 = withResult { try await self.client.fetchUsage(apiKey: key, range: .d7) }
        async let u30 = withResult { try await self.client.fetchUsage(apiKey: key, range: .d30) }
        let (balance, u24Result, u7Result, u30Result) = await (balanceResult, u24, u7, u30)

        for (range, result) in [(UsageRange.h24, u24Result), (.d7, u7Result), (.d30, u30Result)] {
            if case .success(let response) = result {
                usageResponses[range] = response
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
    }

    private func withResult<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func makeViewModel() -> PopoverViewModel {
        let model = PopoverViewModel()
        model.onKeyEntered = { [weak self] raw in
            self?.saveKey(raw)
        }
        return model
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let controller = NSHostingController(rootView: DashboardView(model: viewModel))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        return popover
    }

    @objc private func statusItemClicked() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if let closed = lastCloseDate, Date().timeIntervalSince(closed) < 0.35 {
            return
        }
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func saveKey(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try keychain.write(value)
            apiKey = value
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not store the key"
            alert.informativeText = "Check that the app has Keychain access."
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        render()
        Task { await runCycle() }
    }

    private func render() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderTitle()
            self.syncViewModel()
        }
    }

    private func renderTitle() {
        guard let button = statusItem?.button else { return }

        if apiKey == nil {
            button.attributedTitle = plainTitle("Set key")
            return
        }

        guard let good = lastGood else {
            switch lastBalanceError {
            case .unauthorized:
                button.attributedTitle = plainTitle("Auth error")
            case .transport, .badResponse:
                button.attributedTitle = plainTitle("Offline")
            case .rateLimited:
                button.attributedTitle = plainTitle("Rate limited")
            default:
                button.attributedTitle = plainTitle("...")
            }
            return
        }

        switch lastBalanceError {
        case .unauthorized:
            button.attributedTitle = plainTitle("Auth error")
        case .transport, .badResponse:
            button.attributedTitle = plainTitle("Offline")
        default:
        renderMetric(good, into: button)
        }
    }

    private func renderMetric(_ snapshot: BalanceSnapshot, into button: NSButton) {
        let included = snapshot.included

        if snapshot.isCreditShape,
           let balance = included.balanceUsd,
           let allowance = included.allowanceUsd,
           allowance > 0 {
            guard let from = CloudDates.parse(included.period?.from),
                  let until = CloudDates.parse(included.period?.until),
                  until > from else {
                button.attributedTitle = plainTitle("--")
                return
            }
            let usedPercent = (1 - balance / allowance) * 100
            let span = until.timeIntervalSince(from)
            var elapsedPercent = Date().timeIntervalSince(from) / span * 100
            elapsedPercent = max(0, min(100, elapsedPercent))
            let (text, color) = Metrics.creditDelta(usedPercent: usedPercent, elapsedPercent: elapsedPercent)
            button.attributedTitle = attributedTitle(text, color: color)
            return
        }

        if snapshot.isLegacyShape {
            let now = Date()
            let summary = Metrics.legacySummary(
                sessionRemainingPercent: DisplayAssembly.clampPercentage(included.session?.remainingPercent ?? 0),
                sessionTtl: CloudDates.parse(included.session?.resetsAt)?.timeIntervalSince(now),
                weeklyRemainingPercent: DisplayAssembly.clampPercentage(included.weekly?.remainingPercent ?? 0),
                weeklyTtl: CloudDates.parse(included.weekly?.resetsAt)?.timeIntervalSince(now)
            )
            button.attributedTitle = plainTitle(summary)
            return
        }

        button.attributedTitle = plainTitle("--")
    }

    private func menuBarIcon() -> NSImage? {
        let source = Bundle.main.image(forResource: "menu-bar-icon")
            ?? Bundle.main.image(forResource: "menu-bar-icon@2x")
        guard let image = source else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 22, height: 22)
        return image
    }

    private func syncViewModel() {
        viewModel.usageResponses = usageResponses
        viewModel.updatedAt = lastGood?.fetchedAt
        viewModel.hasStoredKey = apiKey != nil

        if apiKey == nil {
            viewModel.showKeyForm = true
            viewModel.banner = Banner(style: .info, text: "No API key set. Enter your ollama.com API key to sync usage.")
            viewModel.data = nil
            return
        }

        if lastBalanceError == .unauthorized {
            viewModel.showKeyForm = true
            viewModel.banner = Banner(style: .error, text: "API key rejected. Enter a valid key.")
            viewModel.data = nil
            return
        }

        let assembled = lastGood.flatMap { assembleData(for: $0) }

        switch lastBalanceError {
        case .unauthorized:
            viewModel.showKeyForm = true
            viewModel.data = nil
            viewModel.banner = Banner(style: .error, text: "API key rejected. Enter a valid key.")
        case .transport, .badResponse:
            viewModel.showKeyForm = false
            viewModel.data = assembled
            viewModel.banner = Banner(
                style: .error,
                text: assembled != nil ? "Offline - showing last known data." : "Offline - retrying every 60 s."
            )
        case .rateLimited:
            viewModel.showKeyForm = false
            viewModel.data = assembled
            viewModel.banner = Banner(style: .warning, text: "Rate limited - showing last known data.")
        case .missingKey:
            viewModel.showKeyForm = true
            viewModel.data = nil
            viewModel.banner = nil
        case .none:
            viewModel.showKeyForm = false
            viewModel.data = assembled
            viewModel.banner = assembled == nil && lastGood != nil
                ? Banner(style: .warning, text: "Balance data format unexpected.")
                : nil
        }
    }

    private func assembleData(for snapshot: BalanceSnapshot) -> DashboardData? {
        if snapshot.isCreditShape {
            return DisplayAssembly.credit(
                snapshot,
                usageResponses: usageResponses,
                selectedRange: viewModel.selectedRange,
                now: Date()
            ).map { DashboardData.credit($0) }
        }
        if snapshot.isLegacyShape {
            return DisplayAssembly.legacy(snapshot, now: Date()).map { DashboardData.legacy($0) }
        }
        return nil
    }

    private func plainTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text)
    }

    private func attributedTitle(_ text: String, color: MetricColor) -> NSAttributedString {
        let nsColor: NSColor
        switch color {
        case .red: nsColor = .systemRed
        case .green: nsColor = .systemGreen
        case .neutral: nsColor = .labelColor
        }
        return NSAttributedString(string: text, attributes: [.foregroundColor: nsColor])
    }
}

extension AppCoordinator: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        lastCloseDate = Date()
    }
}
