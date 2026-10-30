import Cocoa
import Foundation

struct ProviderItem: Codable {
    let id: String
    let short: String
    let name: String
    let menu_text: String
    let details: [String]
}

struct StatsPayload: Codable {
    var active: String
    var updated_at: Int
    var updated_text: String
    var providers: [ProviderItem]
}

class UsageTrackerApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var refreshTimer: Timer?
    
    private var stats: StatsPayload?
    
    private var scriptDir: String {
        let execPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let url = URL(fileURLWithPath: execPath).resolvingSymlinksInPath().deletingLastPathComponent()
        return url.path
    }
    
    private var statsPath: String {
        return (scriptDir as NSString).appendingPathComponent("stats.json")
    }
    
    private var fetcherPath: String {
        return (scriptDir as NSString).appendingPathComponent("fetcher.py")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "AGY: --"
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        }
        
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        
        loadStats()
        rebuildMenu()
        
        // Auto refresh every 5 minutes (300 seconds)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.triggerFetch()
        }
        
        // Initial fetch in background if stats is missing or older than 5 mins
        let age = stats.map { Date().timeIntervalSince1970 - Double($0.updated_at) } ?? 9999
        if age > 300 {
            triggerFetch()
        }
    }

    func loadStats() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statsPath)),
              let payload = try? JSONDecoder().decode(StatsPayload.self, from: data) else {
            return
        }
        self.stats = payload
    }

    func rebuildMenu() {
        menu.removeAllItems()
        
        guard let stats = stats, !stats.providers.isEmpty else {
            let emptyItem = NSMenuItem(title: "No usage data (Click Refresh)", action: #selector(refreshClicked), keyEquivalent: "")
            emptyItem.target = self
            menu.addItem(emptyItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q"))
            return
        }

        // 1. Update Menu Bar Status Item Button
        let activeProvider = stats.providers.first(where: { $0.id == stats.active }) ?? stats.providers[0]
        if let button = statusItem.button {
            button.title = activeProvider.menu_text
        }

        // 2. Build Provider Selection Section
        for provider in stats.providers {
            let isCurrent = (provider.id == stats.active)
            
            // Header item with checkmark
            let item = NSMenuItem(
                title: "\(provider.name)  [\(provider.menu_text)]",
                action: #selector(providerClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = provider.id
            item.state = isCurrent ? .on : .off
            menu.addItem(item)
            
            // Detail lines (indented and disabled)
            for detail in provider.details {
                let subItem = NSMenuItem(title: "    " + detail, action: nil, keyEquivalent: "")
                subItem.isEnabled = false
                menu.addItem(subItem)
            }
            
            menu.addItem(NSMenuItem.separator())
        }

        // 3. Footer controls
        let updateText = "Last updated: \(stats.updated_text)"
        let statusItemInfo = NSMenuItem(title: updateText, action: nil, keyEquivalent: "")
        statusItemInfo.isEnabled = false
        menu.addItem(statusItemInfo)
        
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc func providerClicked(_ sender: NSMenuItem) {
        guard let providerId = sender.representedObject as? String else { return }
        guard var currentStats = stats else { return }
        
        currentStats.active = providerId
        self.stats = currentStats
        
        // Save active provider to stats.json
        if let encoded = try? JSONEncoder().encode(currentStats) {
            try? encoded.write(to: URL(fileURLWithPath: statsPath))
        }
        
        rebuildMenu()
    }

    @objc func refreshClicked() {
        if let button = statusItem.button {
            button.title = "Updating..."
        }
        triggerFetch()
    }

    func triggerFetch() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            proc.arguments = [self.fetcherPath]
            
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                print("Failed to run fetcher: \(error)")
            }
            
            DispatchQueue.main.async {
                self.loadStats()
                self.rebuildMenu()
            }
        }
    }

    @objc func quitClicked() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = UsageTrackerApp()
app.delegate = delegate
app.run()
