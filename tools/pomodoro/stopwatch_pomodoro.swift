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
    struct Session: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let duration: Int
        
        var timeString: String {
            let hours = Double(duration) / 3600.0
            return String(format: "%g", (hours * 100).rounded() / 100)
        }
    }
    
    @Published var history: [Session] = []
    @Published var isPaused: Bool = false
    @Published var sessionCount: Int = 1
}

struct PomodoroPopoverView: View {
    @ObservedObject var state: PomodoroState
    var onLap: () -> Void
    var onTogglePause: () -> Void
    var onQuit: () -> Void
    var onCopyFocus: () -> Void
    var onCopyFull: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header & Quit Button
            HStack(spacing: 8) {
                Text("Log")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                if !state.history.isEmpty {
                    HStack(spacing: 6) {
                        Button(action: onCopyFocus) {
                            HStack(spacing: 2) {
                                Image(systemName: "doc.on.doc")
                                Text("Focus")
                                    .fixedSize()
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: onCopyFull) {
                            HStack(spacing: 2) {
                                Image(systemName: "doc.on.doc")
                                Text("Full")
                                    .fixedSize()
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button(action: onQuit) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            // History List
            ScrollView {
                VStack(spacing: 0) {
                    if state.history.isEmpty {
                        Text("No logs yet.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .padding(.top, 15)
                    } else {
                        // Table Header
                        HStack {
                            Text("Session")
                            Spacer()
                            Text("Duration (h)")
                        }
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                        .padding(.bottom, 3)
                        
                        Divider()
                            .padding(.bottom, 3)
                        
                        ForEach(state.history) { session in
                            HStack {
                                Text("\(session.icon) \(session.title)")
                                Spacer()
                                Text(session.timeString)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.vertical, 3)
                            
                            Divider()
                                .opacity(0.3)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Control Buttons
            Group {
                if #available(iOS 26, macOS 15, *) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                onLap()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "flag.fill")
                                        .font(.system(size: 11))
                                    Text("Lap")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .font(.system(size: 11))
                            }
                            .glassEffect(.regular.tint(.clear).interactive(), in: .capsule)
                            .buttonStyle(.borderless)
                           
                            Button {
                                onTogglePause()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                                        .font(.system(size: 11))
                                    Text(state.isPaused ? "Resume" : "Pause")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .font(.system(size: 11))
                            }
                            .glassEffect(.regular.tint(.clear).interactive(), in: .capsule)
                            .buttonStyle(.borderless)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Button {
                            onLap()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 11))
                                Text("Lap")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .font(.system(size: 11))
                        }
                        .background(.ultraThinMaterial, in: Capsule())
                        .buttonStyle(.borderless)
                       
                        Button {
                            onTogglePause()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 11))
                                Text(state.isPaused ? "Resume" : "Pause")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .font(.system(size: 11))
                        }
                        .background(.ultraThinMaterial, in: Capsule())
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 190, height: 200)
        .background {
            if #available(iOS 26, macOS 15, *) {
                Color.clear
                    .glassEffect(.regular.tint(.clear), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VisualEffectView().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .preferredColorScheme(.dark)
    }
}


class SmartPomodoro: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var currentSeconds: Int = 0
    
    let pomodoroState = PomodoroState()
    var isFocusSession: Bool {
        return pomodoroState.sessionCount % 2 != 0
    }
    
    let panel = PomodoroPanel()
    var localEventMonitor: Any?
    var globalEventMonitor: Any?

    override init() {
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
    
    // MARK: - Core Stopwatch Logic
    func startTimer() {
        timer?.invalidate()
        updateDisplay()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if !self.pomodoroState.isPaused {
                self.currentSeconds += 1
                self.updateDisplay()
            }
        }
    }
    
    func updateDisplay() {
        DispatchQueue.main.async {
            let timeStr: String
            if self.currentSeconds < 3600 {
                let mins = self.currentSeconds / 60
                let secs = self.currentSeconds % 60
                timeStr = String(format: "%02d:%02d", mins, secs)
            } else {
                let hours = self.currentSeconds / 3600
                let mins = (self.currentSeconds % 3600) / 60
                timeStr = String(format: "%02d:%02d", hours, mins)
            }
            
            let icon = self.isFocusSession ? "🍅" : "☕️"
            let sessionType = self.isFocusSession ? "Focus" : "Break"
            let displayTask = sessionType
            
            if self.pomodoroState.isPaused {
                self.statusItem.button?.title = "⏸ \(displayTask) [\(timeStr)]"
            } else {
                self.statusItem.button?.title = "\(icon) \(displayTask) [\(timeStr)]"
            }
        }
    }

    // MARK: - Actions
    @objc func recordLap() {
        let sessionType = isFocusSession ? "Focus" : "Break"
        
        let newSession = PomodoroState.Session(
            title: sessionType,
            icon: isFocusSession ? "🍅" : "☕️",
            duration: currentSeconds
        )
        
        // Chèn phiên vừa hoàn thành lên đầu danh sách
        pomodoroState.history.insert(newSession, at: 0)
        
        // Cập nhật state sang phiên tiếp theo và reset thời gian
        pomodoroState.sessionCount += 1
        currentSeconds = 0
        pomodoroState.isPaused = false
        
        updateDisplay()
    }

    @objc func togglePause() {
        pomodoroState.isPaused.toggle()
        updateDisplay()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func copyTotalFocus() {
        let totalFocusSeconds = pomodoroState.history.filter { $0.title == "Focus" }.reduce(0) { $0 + $1.duration }
        let hours = Double(totalFocusSeconds) / 3600.0
        let timeString = String(format: "%g", (hours * 100).rounded() / 100)
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(timeString, forType: .string)
    }

    @objc func copyTotalTime() {
        let totalSeconds = pomodoroState.history.reduce(0) { $0 + $1.duration }
        let hours = Double(totalSeconds) / 3600.0
        let timeString = String(format: "%g", (hours * 100).rounded() / 100)
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(timeString, forType: .string)
    }

    // MARK: - UI SETUP
    func setupPopover() {
        let rootView = PomodoroPopoverView(
            state: pomodoroState,
            onLap: { [weak self] in self?.recordLap() },
            onTogglePause: { [weak self] in self?.togglePause() },
            onQuit: { [weak self] in self?.quitApp() },
            onCopyFocus: { [weak self] in self?.copyTotalFocus() },
            onCopyFull: { [weak self] in self?.copyTotalTime() }
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
            
            let panelSize = NSSize(width: 190, height: 200)
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
let delegate = SmartPomodoro()
app.delegate = delegate
app.run()