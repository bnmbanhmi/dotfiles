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

class PomodoroPanel: NSPanel {
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

class PomodoroState: ObservableObject {
    @Published var isBreak: Bool = false
}

struct PomodoroPopoverView: View {
    @AppStorage("PomodoroNotepad") var notepadText: String = ""
    @ObservedObject var state: PomodoroState
    var onMainAction: () -> Void
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
            
            HStack(spacing: 16) {
                Button {
                    onMainAction()
                } label: {
                    HStack {
                        Image(systemName: state.isBreak ? "play.fill" : "cup.and.saucer.fill")
                            .font(.system(size: 26))
                        Text(state.isBreak ? "Focus" : "Break")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .font(.title2)
                }
                .clipShape(Capsule())
                .glassEffect()
                .buttonStyle(.borderless)
               
                Button {
                    onQuit()
                } label: {
                    HStack {
                        Image(systemName: "power")
                            .font(.system(size: 26))
                        Text("Quit")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .font(.title2)
                }
                .clipShape(Capsule())
                .glassEffect()
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .frame(width: 300, height: 260)
        .background(VisualEffectView().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .preferredColorScheme(.dark)
    }
}

class SmartPomodoro: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var baseMinutes: Int
    var initialSeconds: Int
    var currentSeconds: Int
    
    let pomodoroState = PomodoroState()
    var isBreak: Bool {
        get { pomodoroState.isBreak }
        set { pomodoroState.isBreak = newValue }
    }
    
    var isOvertime: Bool = false
    
    // UI Elements
    let panel = PomodoroPanel()
    var localEventMonitor: Any?
    var globalEventMonitor: Any?
    
    // Persistence
    let defaultNotepadText = "Focus on: \n\n(Notes here...)"
    var notepadText: String {
        get { UserDefaults.standard.string(forKey: "PomodoroNotepad") ?? defaultNotepadText }
        set { UserDefaults.standard.set(newValue, forKey: "PomodoroNotepad") }
    }
    
    var firstLine: String {
        let lines = notepadText.components(separatedBy: .newlines)
        return lines.first?.trimmingCharacters(in: .whitespaces) ?? "No task"
    }

    init(minutes: Int) {
        self.baseMinutes = minutes
        self.initialSeconds = minutes * 60
        self.currentSeconds = self.initialSeconds
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        setupPopover()
        
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        startTimer()
    }
    
    // MARK: - Core Timer Logic
    func startTimer() {
        timer?.invalidate()
        updateDisplay()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if !self.isOvertime {
                self.currentSeconds -= 1
                if self.currentSeconds <= 0 {
                    self.isOvertime = true
                    self.currentSeconds = 0
                    NSSound(named: "Glass")?.play()
                }
            } else {
                self.currentSeconds += 1
            }
            self.updateDisplay()
        }
    }
    
    func updateDisplay() {
        DispatchQueue.main.async {
            let maxLen = 25
            let title = self.firstLine
            let displayTask = title.count > maxLen ? String(title.prefix(maxLen-3)) + "..." : title
            
            let mins = self.currentSeconds / 60
            let secs = self.currentSeconds % 60
            
            if self.isOvertime {
                let timeStr = String(format: "+%02d:%02d", mins, secs)
                self.statusItem.button?.title = "🔥 \(displayTask) [\(timeStr)]"
            } else {
                let timeStr = String(format: "%02d:%02d", mins, secs)
                let icon = self.isBreak ? "☕️" : "🍅"
                self.statusItem.button?.title = "\(icon) \(displayTask) [\(timeStr)]"
            }
        }
    }

    // MARK: - Actions
    @objc func endSessionAndStartBreak() {
        let breakMins = max(1, self.baseMinutes / 5) 
        self.isBreak = true
        self.isOvertime = false
        self.initialSeconds = breakMins * 60
        self.currentSeconds = self.initialSeconds
        startTimer()
    }

    @objc func startNewFocusSession() {
        self.isBreak = false
        self.isOvertime = false
        self.initialSeconds = self.baseMinutes * 60 
        self.currentSeconds = self.initialSeconds
        startTimer()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - THE LIQUID GLASS UI SETUP
    func setupPopover() {
        let rootView = PomodoroPopoverView(
            state: pomodoroState,
            onMainAction: { [weak self] in self?.handleMainAction() },
            onQuit: { [weak self] in self?.quitApp() },
            onTextChanged: { [weak self] in self?.updateDisplay() }
        )
        let hostingController = NSHostingController(rootView: rootView)
        panel.contentViewController = hostingController
    }

    @objc func handleMainAction() {
        if isBreak { startNewFocusSession() } else { endSessionAndStartBreak() }
        hidePanel()
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button, let window = button.window else { return }
        
        if panel.isVisible {
            hidePanel()
        } else {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = window.convertToScreen(buttonRect)
            
            let panelSize = NSSize(width: 300, height: 260)
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
let args = CommandLine.arguments
let inputMinutes = args.count > 1 ? (Int(args[1]) ?? 25) : 25
let delegate = SmartPomodoro(minutes: inputMinutes)
app.delegate = delegate
app.run()