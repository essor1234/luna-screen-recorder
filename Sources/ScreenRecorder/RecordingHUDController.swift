import AppKit

public enum BarMode {
    case ready
    case recording
}

public enum HUDCaptureMode: Int {
    case area = 0
    case window = 1
    case screen = 2
}

public final class RecordingHUDController: NSObject {
    public static let shared = RecordingHUDController()
    
    private var window: NSPanel?
    private var visualEffectView: NSVisualEffectView?
    private var currentMode: BarMode = .ready
    private var selectedCaptureMode: HUDCaptureMode = .area
    private var wasVisibleBeforeSelection = false
    private var hasCustomPosition = false
    
    // Containers for the two modes
    private var readyContainer: NSView?
    private var recordingContainer: NSView?
    
    // Ready Bar UI elements
    private var areaModeButton: NSButton?
    private var windowModeButton: NSButton?
    private var screenModeButton: NSButton?
    private var systemAudioPill: NSButton?
    private var micPill: NSButton?
    private var recordButton: NSButton?
    private var libraryButton: NSButton?
    private var closeButton: NSButton?
    
    // Recording HUD UI elements
    private var statusDot: NSView?
    private var timerLabel: NSTextField?
    private var recSysAudioButton: NSButton?
    private var recMicButton: NSButton?
    private var pauseButton: NSButton?
    private var stopButton: NSButton?
    
    public var onTogglePause: (() -> Void)?
    public var onStop: (() -> Void)?
    
    private var isPaused = false
    
    public var hudWindowNumber: Int? {
        return window?.windowNumber
    }
    
    public var isVisible: Bool {
        return window?.isVisible ?? false
    }
    
    private let readyWidth: CGFloat = 620
    private let recordingWidth: CGFloat = 345
    private let barHeight: CGFloat = 44
    
    private override init() {
        super.init()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioInputsChanged),
            name: RetentionManager.systemAudioDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioInputsChanged),
            name: MicrophoneManager.selectionDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(floatingBarVisibilityPreferenceChanged),
            name: RetentionManager.floatingBarVisibilityDidChangeNotification,
            object: nil
        )
    }
    
    public func prepareWindow() {
        if window == nil {
            createWindow()
        }
    }
    
    // MARK: - Mode 1: Ready / Idle Floating Toolbar
    public func showIdleBar() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.window == nil {
                self.createWindow()
            }
            
            self.currentMode = .ready
            self.stopPulseAnimation()
            
            self.readyContainer?.frame = NSRect(x: 0, y: 0, width: self.readyWidth, height: self.barHeight)
            self.readyContainer?.isHidden = false
            self.recordingContainer?.isHidden = true
            
            self.setWindowWidth(self.readyWidth, animated: self.window?.isVisible == true)
            self.updateModeButtons()
            self.updateAudioPills()
            
            if !self.hasCustomPosition {
                self.positionWindow(width: self.readyWidth)
            }
            
            self.window?.orderFrontRegardless()
        }
    }
    
    public func hideForSelection() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.wasVisibleBeforeSelection = (self.window?.isVisible == true)
            self.window?.orderOut(nil)
        }
    }
    
    public func showIdleBarIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.wasVisibleBeforeSelection || RetentionManager.shared.isFloatingBarVisible {
                self.showIdleBar()
            }
        }
    }
    
    // MARK: - Mode 2: Active Recording HUD
    public func show(onTogglePause: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onTogglePause = onTogglePause
        self.onStop = onStop
        self.isPaused = false
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.window == nil {
                self.createWindow()
            }
            
            self.currentMode = .recording
            self.readyContainer?.isHidden = true
            self.recordingContainer?.frame = NSRect(x: 0, y: 0, width: self.recordingWidth, height: self.barHeight)
            self.recordingContainer?.isHidden = false
            
            self.setWindowWidth(self.recordingWidth, animated: true)
            self.updateUI(seconds: 0, isPaused: false)
            self.updateRecAudioControls()
            self.startPulseAnimation()
            
            self.window?.orderFrontRegardless()
        }
    }
    
    public func finishRecording() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopPulseAnimation()
            
            if RetentionManager.shared.isFloatingBarVisible {
                self.showIdleBar()
            } else {
                self.hide()
            }
        }
    }
    
    public func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.stopPulseAnimation()
            self?.window?.orderOut(nil)
        }
    }
    
    public func updateTimer(seconds: Int, isPaused: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPaused = isPaused
            self?.updateUI(seconds: seconds, isPaused: isPaused)
        }
    }
    
    // MARK: - Layout & Window Positioning
    private func positionWindow(width: CGFloat) {
        guard !hasCustomPosition else { return }
        guard let window = self.window, let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let x = screenRect.midX - (width / 2)
        let y = screenRect.maxY - 72
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func setWindowWidth(_ newWidth: CGFloat, animated: Bool) {
        guard let window = self.window else { return }
        let oldFrame = window.frame
        let newX = oldFrame.midX - (newWidth / 2)
        let newFrame = NSRect(x: newX, y: oldFrame.origin.y, width: newWidth, height: barHeight)
        
        self.visualEffectView?.frame = NSRect(x: 0, y: 0, width: newWidth, height: barHeight)
        if newWidth == readyWidth {
            self.readyContainer?.frame = NSRect(x: 0, y: 0, width: readyWidth, height: barHeight)
        } else {
            self.recordingContainer?.frame = NSRect(x: 0, y: 0, width: recordingWidth, height: barHeight)
        }
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }
    
    private func createWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: readyWidth, height: barHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            self?.hasCustomPosition = true
        }
        
        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 22
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        
        self.visualEffectView = visualEffect
        
        setupReadyContainer(in: visualEffect)
        setupRecordingContainer(in: visualEffect)
        
        panel.contentView = visualEffect
        self.window = panel
        
        updateModeButtons()
        updateAudioPills()
    }
    
    // MARK: - Setup Ready Container (Idle Toolbar)
    private func setupReadyContainer(in parentView: NSView) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: readyWidth, height: barHeight))
        
        // 1. Capture Modes: Area, Window, Screen
        let areaBtn = createPillButton(frame: NSRect(x: 10, y: 7, width: 68, height: 30), title: "⌖ Area", action: #selector(areaModeClicked))
        areaBtn.toolTip = "Record a selected portion of the screen (⌘⌥1)"
        container.addSubview(areaBtn)
        self.areaModeButton = areaBtn
        
        let windowBtn = createPillButton(frame: NSRect(x: 80, y: 7, width: 78, height: 30), title: "🪟 Window", action: #selector(windowModeClicked))
        windowBtn.toolTip = "Record a specific window or display (⌘⌥2)"
        container.addSubview(windowBtn)
        self.windowModeButton = windowBtn
        
        let screenBtn = createPillButton(frame: NSRect(x: 160, y: 7, width: 78, height: 30), title: "🖥️ Screen", action: #selector(screenModeClicked))
        screenBtn.toolTip = "Record the entire active display (⌘⌥3)"
        container.addSubview(screenBtn)
        self.screenModeButton = screenBtn
        
        // Divider 1
        let div1 = createDivider(x: 244)
        container.addSubview(div1)
        
        // 2. Audio Inputs Section (Always visible so users see audio inputs clearly)
        let sysPill = createPillButton(frame: NSRect(x: 252, y: 7, width: 90, height: 30), title: "Sys: ON", action: #selector(sysAudioPillClicked))
        container.addSubview(sysPill)
        self.systemAudioPill = sysPill
        
        let mic = createPillButton(frame: NSRect(x: 348, y: 7, width: 116, height: 30), title: "Mic ▾", action: #selector(micPillClicked))
        container.addSubview(mic)
        self.micPill = mic
        
        // Divider 2
        let div2 = createDivider(x: 470)
        container.addSubview(div2)
        
        // 3. Action Buttons: Record, Library, Close
        let recBtn = NSButton(frame: NSRect(x: 478, y: 7, width: 84, height: 30))
        recBtn.bezelStyle = .inline
        recBtn.isBordered = false
        recBtn.wantsLayer = true
        recBtn.layer?.cornerRadius = 15
        recBtn.layer?.backgroundColor = NSColor.systemRed.cgColor
        recBtn.title = " Record"
        recBtn.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Record")
        recBtn.imagePosition = .imageLeading
        recBtn.font = NSFont.systemFont(ofSize: 12.5, weight: .bold)
        recBtn.contentTintColor = .white
        recBtn.toolTip = "Start Recording (⌘⌥1/⌘⌥2/⌘⌥3)"
        recBtn.target = self
        recBtn.action = #selector(recordButtonClicked)
        container.addSubview(recBtn)
        self.recordButton = recBtn
        
        let libBtn = NSButton(frame: NSRect(x: 568, y: 8, width: 26, height: 28))
        libBtn.bezelStyle = .inline
        libBtn.isBordered = false
        libBtn.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Library")
        libBtn.imagePosition = .imageOnly
        libBtn.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        libBtn.toolTip = "Open Recordings Library"
        libBtn.target = self
        libBtn.action = #selector(libraryClicked)
        container.addSubview(libBtn)
        self.libraryButton = libBtn
        
        let clsBtn = NSButton(frame: NSRect(x: 596, y: 9, width: 20, height: 26))
        clsBtn.bezelStyle = .inline
        clsBtn.isBordered = false
        clsBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        clsBtn.imagePosition = .imageOnly
        clsBtn.contentTintColor = NSColor.white.withAlphaComponent(0.5)
        clsBtn.toolTip = "Hide Floating Bar (⌘⌥F to reopen)"
        clsBtn.target = self
        clsBtn.action = #selector(closeClicked)
        container.addSubview(clsBtn)
        self.closeButton = clsBtn
        
        parentView.addSubview(container)
        self.readyContainer = container
    }
    
    // MARK: - Setup Recording Container (Active HUD)
    private func setupRecordingContainer(in parentView: NSView) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: recordingWidth, height: barHeight))
        container.isHidden = true
        
        // Red Recording Status Dot with shadow
        let dot = NSView(frame: NSRect(x: 16, y: 17, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.shadowColor = NSColor.systemRed.cgColor
        dot.layer?.shadowRadius = 4
        dot.layer?.shadowOpacity = 0.8
        dot.layer?.shadowOffset = .zero
        container.addSubview(dot)
        self.statusDot = dot
        
        // Monospaced SF Pro Timer
        let label = NSTextField(labelWithString: "00:00")
        label.frame = NSRect(x: 32, y: 12, width: 62, height: 20)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.alignment = .left
        container.addSubview(label)
        self.timerLabel = label
        
        // Divider 1
        let div1 = createDivider(x: 98)
        container.addSubview(div1)
        
        // Live Audio Inputs in Recording Mode
        let sysBtn = NSButton(frame: NSRect(x: 106, y: 8, width: 30, height: 28))
        sysBtn.bezelStyle = .inline
        sysBtn.isBordered = false
        sysBtn.imagePosition = .imageOnly
        sysBtn.target = self
        sysBtn.action = #selector(recSysAudioClicked)
        container.addSubview(sysBtn)
        self.recSysAudioButton = sysBtn
        
        let micBtn = NSButton(frame: NSRect(x: 140, y: 8, width: 85, height: 28))
        micBtn.bezelStyle = .inline
        micBtn.isBordered = false
        micBtn.imagePosition = .imageLeading
        micBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        micBtn.target = self
        micBtn.action = #selector(recMicClicked)
        container.addSubview(micBtn)
        self.recMicButton = micBtn
        
        // Divider 2
        let div2 = createDivider(x: 231)
        container.addSubview(div2)
        
        // Pause / Resume Button
        let pauseBtn = NSButton(frame: NSRect(x: 239, y: 8, width: 32, height: 28))
        pauseBtn.bezelStyle = .inline
        pauseBtn.isBordered = false
        pauseBtn.wantsLayer = true
        pauseBtn.layer?.cornerRadius = 14
        pauseBtn.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
        pauseBtn.imagePosition = .imageOnly
        pauseBtn.contentTintColor = .white
        pauseBtn.toolTip = "Pause Recording (⌘⌥P)"
        pauseBtn.target = self
        pauseBtn.action = #selector(pauseClicked)
        container.addSubview(pauseBtn)
        self.pauseButton = pauseBtn
        
        // Stop Button (High-contrast, fully clickable inline pill)
        let stopBtn = NSButton(frame: NSRect(x: 275, y: 7, width: 62, height: 30))
        stopBtn.bezelStyle = .inline
        stopBtn.isBordered = false
        stopBtn.wantsLayer = true
        stopBtn.layer?.cornerRadius = 15
        stopBtn.layer?.backgroundColor = NSColor.systemRed.cgColor
        stopBtn.title = " Stop"
        stopBtn.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
        stopBtn.imagePosition = .imageLeading
        stopBtn.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        stopBtn.contentTintColor = .white
        stopBtn.toolTip = "Stop Recording (⌘⌥S)"
        stopBtn.target = self
        stopBtn.action = #selector(stopClicked)
        container.addSubview(stopBtn)
        self.stopButton = stopBtn
        
        parentView.addSubview(container)
        self.recordingContainer = container
    }
    
    // MARK: - UI Helpers
    private func createPillButton(frame: NSRect, title: String, action: Selector) -> NSButton {
        let btn = NSButton(frame: frame)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 14
        btn.layer?.masksToBounds = true
        btn.title = title
        btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        btn.imagePosition = .imageLeading
        btn.target = self
        btn.action = action
        return btn
    }
    
    private func createDivider(x: CGFloat) -> NSView {
        let div = NSView(frame: NSRect(x: x, y: 11, width: 1, height: 22))
        div.wantsLayer = true
        div.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        return div
    }
    
    // MARK: - Update States
    private func updateModeButtons() {
        let modes: [(btn: NSButton?, mode: HUDCaptureMode)] = [
            (areaModeButton, .area),
            (windowModeButton, .window),
            (screenModeButton, .screen)
        ]
        
        for item in modes {
            guard let btn = item.btn else { continue }
            let isSelected = (selectedCaptureMode == item.mode)
            if isSelected {
                btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
                btn.contentTintColor = .white
                btn.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            } else {
                btn.layer?.backgroundColor = NSColor.clear.cgColor
                btn.contentTintColor = NSColor.white.withAlphaComponent(0.72)
                btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            }
        }
    }
    
    public func updateAudioPills() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Ready Bar System Audio
            let sysOn = RetentionManager.shared.isSystemAudioEnabled
            if sysOn {
                self.systemAudioPill?.title = "Sys: ON"
                self.systemAudioPill?.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
                self.systemAudioPill?.contentTintColor = .systemGreen
                self.systemAudioPill?.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.16).cgColor
                self.systemAudioPill?.layer?.borderWidth = 0.5
                self.systemAudioPill?.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.4).cgColor
                self.systemAudioPill?.toolTip = "System Audio is ON (Internal sounds and tabs captured). Click to toggle."
            } else {
                self.systemAudioPill?.title = "Sys: OFF"
                self.systemAudioPill?.image = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: nil)
                self.systemAudioPill?.contentTintColor = NSColor.white.withAlphaComponent(0.45)
                self.systemAudioPill?.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
                self.systemAudioPill?.layer?.borderWidth = 0.5
                self.systemAudioPill?.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
                self.systemAudioPill?.toolTip = "System Audio is OFF. Click to turn ON."
            }
            
            // 2. Ready Bar Microphone
            let isMuted = MicrophoneManager.shared.isMuted
            let micName = MicrophoneManager.shared.currentDeviceName
            let shortName = self.abbreviate(micName, maxLen: 12)
            
            if isMuted {
                self.micPill?.title = "Muted ▾"
                self.micPill?.image = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: nil)
                self.micPill?.contentTintColor = .systemOrange
                self.micPill?.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.16).cgColor
                self.micPill?.layer?.borderWidth = 0.5
                self.micPill?.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.4).cgColor
                self.micPill?.toolTip = "Microphone is MUTED. Click to choose a microphone."
            } else {
                self.micPill?.title = "\(shortName) ▾"
                self.micPill?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
                self.micPill?.contentTintColor = .white
                self.micPill?.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
                self.micPill?.layer?.borderWidth = 0.5
                self.micPill?.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
                self.micPill?.toolTip = "Microphone: \(micName). Click to switch input or mute."
            }
            
            // 3. Recording Mode Audio Controls
            self.updateRecAudioControls()
        }
    }
    
    private func updateRecAudioControls() {
        let sysOn = RetentionManager.shared.isSystemAudioEnabled
        recSysAudioButton?.image = NSImage(systemSymbolName: sysOn ? "speaker.wave.2.fill" : "speaker.slash.fill", accessibilityDescription: nil)
        recSysAudioButton?.contentTintColor = sysOn ? .systemGreen : NSColor.white.withAlphaComponent(0.4)
        recSysAudioButton?.toolTip = sysOn ? "System Audio: Active (Click to mute)" : "System Audio: Off (Click to enable)"
        
        let isMuted = MicrophoneManager.shared.isMuted
        let micName = MicrophoneManager.shared.currentDeviceName
        let shortName = abbreviate(micName, maxLen: 8)
        recMicButton?.image = NSImage(systemSymbolName: isMuted ? "mic.slash.fill" : "mic.fill", accessibilityDescription: nil)
        recMicButton?.title = isMuted ? "Muted" : shortName
        recMicButton?.contentTintColor = isMuted ? .systemOrange : .white
        recMicButton?.toolTip = isMuted ? "Microphone: Muted (Click to select mic)" : "Microphone: \(micName) (Click to select mic)"
    }
    
    private func abbreviate(_ text: String, maxLen: Int) -> String {
        if text.count <= maxLen { return text }
        let clean = text.replacingOccurrences(of: "Microphone", with: "Mic")
                        .replacingOccurrences(of: "Built-in", with: "Built-in")
        if clean.count <= maxLen { return clean }
        return "\(clean.prefix(maxLen - 2)).."
    }
    
    private func startPulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.duration = 0.8
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        statusDot?.layer?.add(pulse, forKey: "dot_pulse")
    }
    
    private func stopPulseAnimation() {
        statusDot?.layer?.removeAnimation(forKey: "dot_pulse")
    }
    
    private func updateUI(seconds: Int, isPaused: Bool) {
        let mins = seconds / 60
        let secs = seconds % 60
        timerLabel?.stringValue = String(format: "%02d:%02d", mins, secs)
        
        if isPaused {
            statusDot?.layer?.backgroundColor = NSColor.systemOrange.cgColor
            statusDot?.layer?.shadowColor = NSColor.systemOrange.cgColor
            statusDot?.layer?.removeAnimation(forKey: "dot_pulse")
            statusDot?.alphaValue = 1.0
            pauseButton?.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Resume")
            pauseButton?.toolTip = "Resume Recording (⌘⌥P)"
        } else {
            statusDot?.layer?.backgroundColor = NSColor.systemRed.cgColor
            statusDot?.layer?.shadowColor = NSColor.systemRed.cgColor
            if statusDot?.layer?.animation(forKey: "dot_pulse") == nil {
                startPulseAnimation()
            }
            pauseButton?.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
            pauseButton?.toolTip = "Pause Recording (⌘⌥P)"
        }
    }
    
    // MARK: - Actions
    @objc private func areaModeClicked() {
        selectedCaptureMode = .area
        updateModeButtons()
    }
    
    @objc private func windowModeClicked() {
        selectedCaptureMode = .window
        updateModeButtons()
    }
    
    @objc private func screenModeClicked() {
        selectedCaptureMode = .screen
        updateModeButtons()
    }
    
    @objc private func sysAudioPillClicked() {
        RetentionManager.shared.isSystemAudioEnabled.toggle()
        updateAudioPills()
    }
    
    @objc private func micPillClicked(_ sender: NSButton) {
        let menu = MicrophoneManager.shared.buildMenu { [weak self] in
            self?.updateAudioPills()
        }
        let pt = NSPoint(x: -8, y: -4)
        menu.popUp(positioning: nil, at: pt, in: sender)
    }
    
    @objc private func recordButtonClicked() {
        switch selectedCaptureMode {
        case .area:
            MenuBarController.shared.startAreaRecording()
        case .window:
            MenuBarController.shared.showVisualPicker()
        case .screen:
            MenuBarController.shared.startMainScreenRecording()
        }
    }
    
    @objc private func libraryClicked() {
        RecordingsWindowController.shared.show()
    }
    
    @objc private func closeClicked() {
        hide()
        RetentionManager.shared.isFloatingBarVisible = false
    }
    
    @objc private func recSysAudioClicked() {
        RetentionManager.shared.isSystemAudioEnabled.toggle()
        updateAudioPills()
    }
    
    @objc private func recMicClicked(_ sender: NSButton) {
        let menu = MicrophoneManager.shared.buildMenu { [weak self] in
            self?.updateAudioPills()
        }
        let pt = NSPoint(x: -8, y: -4)
        menu.popUp(positioning: nil, at: pt, in: sender)
    }
    
    @objc private func pauseClicked() {
        print("[RecordingHUDController] Pause clicked on floating HUD")
        if let onTogglePause = self.onTogglePause {
            onTogglePause()
        } else {
            MenuBarController.shared.togglePause()
        }
    }
    
    @objc private func stopClicked() {
        print("[RecordingHUDController] Stop clicked on floating HUD")
        if let onStop = self.onStop {
            onStop()
        } else {
            MenuBarController.shared.stopRecording()
        }
    }
    
    @objc private func audioInputsChanged(_ notification: Notification) {
        updateAudioPills()
    }
    
    @objc private func floatingBarVisibilityPreferenceChanged(_ notification: Notification) {
        if RetentionManager.shared.isFloatingBarVisible {
            showIdleBar()
        } else if currentMode == .ready {
            hide()
        }
    }
}
