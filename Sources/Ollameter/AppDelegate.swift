import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = OllamaClient()
    private var statusItem: NSStatusItem?
    private var pollingTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Ollameter") {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.button?.image = icon
            statusItem?.button?.imageScaling = .scaleProportionallyDown
            statusItem?.button?.title = "Starting"
        } else {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.button?.title = "Ollameter"
        }

        statusItem?.menu = makeMenu(with: nil)
        refresh()
        startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTask?.cancel()
    }

    private func startPolling() {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.refresh()
            }
        }
    }

    private func refresh() {
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let snapshot = try await client.fetchSnapshot()
                self.render(snapshot)
            } catch {
                self.render(OllamaSnapshot(version: nil, models: [], isReachable: false))
            }
        }
    }

    private func render(_ snapshot: OllamaSnapshot) {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.title = snapshot.displayTitle
            self?.statusItem?.menu = self?.makeMenu(with: snapshot)
        }
    }

    private func makeMenu(with snapshot: OllamaSnapshot?) -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: "Ollameter", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let statusText: String
        if let snapshot, snapshot.isReachable {
            statusText = "Ollama is running"
        } else {
            statusText = "Ollama is offline"
        }

        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if let version = snapshot?.version {
            let versionItem = NSMenuItem(title: "Version \(version)", action: nil, keyEquivalent: "")
            versionItem.isEnabled = false
            menu.addItem(versionItem)
        }

        menu.addItem(.separator())

        if let models = snapshot?.models {
            if models.isEmpty {
                let empty = NSMenuItem(title: "No models loaded", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            } else {
                let header = NSMenuItem(title: "Loaded models:", action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)

                for model in models {
                    let name = model.name ?? model.model ?? "Unknown"
                    let memory = OllamaSnapshot.formatBytes(model.sizeVram ?? model.size ?? 0)
                    let item = NSMenuItem(title: "\(name) — \(memory)", action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                }
            }
        } else {
            let unavailable = NSMenuItem(title: "Ollama API unavailable", action: nil, keyEquivalent: "")
            unavailable.isEnabled = false
            menu.addItem(unavailable)
        }

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: "Refresh now",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(
            title: "Quit Ollameter",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
