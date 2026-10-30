import Cocoa
import Foundation

struct MetricItem: Codable {
    let id: String
    let label: String
    let menu_text: String
}

struct MetricGroup: Codable {
    let name: String
    let items: [MetricItem]
}

struct StatsPayload: Codable {
    var active: String
    var updated_at: Int
    var updated_text: String
    var groups: [MetricGroup]
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

    func menuWillOpen(_ menu: NSMenu) {
        loadStats()
        rebuildMenu()
    }

    func rebuildMenu() {
        menu.removeAllItems()
        
        guard let stats = stats, !stats.groups.isEmpty else {
            let emptyItem = NSMenuItem(title: "No usage data (Click Refresh)", action: #selector(refreshClicked), keyEquivalent: "")
            emptyItem.target = self
            menu.addItem(emptyItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q"))
            return
        }

        // 1. Update Menu Bar Status Item Button
        var activeItem: MetricItem? = nil
        for group in stats.groups {
            if let found = group.items.first(where: { $0.id == stats.active }) {
                activeItem = found
                break
            }
        }
        if activeItem == nil, let firstGroup = stats.groups.first, let firstItem = firstGroup.items.first {
            activeItem = firstItem
        }
        
        if let button = statusItem.button, let active = activeItem {
            button.title = active.menu_text
        }

        // 2. Build Groups and Items
        for group in stats.groups {
            // Group header (clean bold secondary color header)
            let headerItem = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            let font = NSFont.boldSystemFont(ofSize: 11)
            let attr = NSAttributedString(string: group.name, attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            headerItem.attributedTitle = attr
            menu.addItem(headerItem)
            
            // Selectable metric items
            for item in group.items {
                let isCurrent = (item.id == stats.active)
                let menuItem = NSMenuItem(
                    title: item.label,
                    action: #selector(metricClicked(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item.id
                menuItem.state = isCurrent ? .on : .off
                menuItem.indentationLevel = 1
                menu.addItem(menuItem)
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

    @objc func metricClicked(_ sender: NSMenuItem) {
        guard let metricId = sender.representedObject as? String else { return }
        guard var currentStats = stats else { return }
        
        currentStats.active = metricId
        self.stats = currentStats
        
        // Save active metric to stats.json
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
