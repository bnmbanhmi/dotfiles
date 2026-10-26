import Cocoa
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

class NotesPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
    }
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

struct NotesPopoverView: View {
    @AppStorage("MenuBarNotes") var notepadText: String = "Notes\n\n(Write here...)"
    var onQuit: () -> Void
    var onTextChanged: () -> Void
    
    var body: some View {
        VStack {
            TextEditor(text: $notepadText)
                .scrollContentBackground(.hidden)
                .font(.title2)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onChange(of: notepadText) { onTextChanged() }
            
            HStack {
                Spacer()
                Button {
                    onQuit()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "power")
                            .font(.system(size: 16))
                        Text("Quit")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .font(.body)
                }
                .clipShape(Capsule())
                .glassEffect()
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .frame(width: 320, height: 280)
        .background(VisualEffectView().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .preferredColorScheme(.dark)
    }
}

class MenuBarNotes: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    
    // UI Elements
    let panel = NotesPanel()
    var localEventMonitor: Any?
    var globalEventMonitor: Any?
    
    // Persistence
    let storageKey = "MenuBarNotes"
    let defaultNotepadText = "Notes\n\n(Write here...)"
    var notepadText: String {
        get { UserDefaults.standard.string(forKey: storageKey) ?? defaultNotepadText }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }
    
    var firstLine: String {
        let lines = notepadText.components(separatedBy: .newlines)
        let first = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "Notes" : first
    }

    override init() {
        super.init()
        UserDefaults.standard.register(defaults: [storageKey: defaultNotepadText])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        setupPopover()
        
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        updateDisplay()
    }
    
    func updateDisplay() {
        DispatchQueue.main.async {
            let maxLen = 30
            let title = self.firstLine
            let displayTask = title.count > maxLen ? String(title.prefix(maxLen - 3)) + "..." : title
            self.statusItem.button?.title = displayTask
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - UI Setup
    func setupPopover() {
        let rootView = NotesPopoverView(
            onQuit: { [weak self] in self?.quitApp() },
            onTextChanged: { [weak self] in self?.updateDisplay() }
        )
        let hostingController = NSHostingController(rootView: rootView)
        panel.contentViewController = hostingController
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button, let window = button.window else { return }
        
        if panel.isVisible {
            hidePanel()
        } else {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = window.convertToScreen(buttonRect)
            
            let panelSize = NSSize(width: 320, height: 280)
            let panelX = screenRect.midX - (panelSize.width / 2)
            let panelY = screenRect.minY - panelSize.height - 4
            
            panel.setFrame(NSRect(origin: NSPoint(x: panelX, y: panelY), size: panelSize), display: true)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            if localEventMonitor == nil {
                localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    if let self = self, self.panel.isVisible {
                        if event.window != self.panel {
                            self.hidePanel()
                            return nil 
                        }
                    }
                    return event
                }
            }
            
            if globalEventMonitor == nil {
                globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    if let self = self, self.panel.isVisible {
                        self.hidePanel()
                    }
                }
            }
        }
    }
    
    func hidePanel() {
        panel.orderOut(nil)
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }
}

// Entry Point
let app = NSApplication.shared
let delegate = MenuBarNotes()
app.delegate = delegate
app.run()
