import Cocoa
import SwiftUI
import UserNotifications

// Moved out of AppDelegate so other files (e.g., SettingsWindow.swift) can reference it
enum DisplayMode: Hashable {
    case time
    case progress
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var isWorkSession = true
    var timeRemaining = 25 * 60
    // Start in paused state; user must manually resume
    var isPaused = true

    // Display mode and durations
    var displayMode: DisplayMode = .time
    var workDuration: Int = 25 * 60
    var breakDuration: Int = 5 * 60
    var settingsWindowController: NSWindowController?

    // DisplayMode enum now top-level

    func applicationDidFinishLaunching(_ notification: Notification) {
    // Use accessory activation policy so app does NOT show in Dock but can present windows
    NSApp.setActivationPolicy(.accessory)
        
        // Request notification permissions & set delegate so notifications appear while app is frontmost
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if !granted {
                // Could log or update UI if needed
            }
        }
        
    // Create the status bar item (no icon, we'll show only text)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
    buildMenu()
    workDuration = 25 * 60
    breakDuration = 5 * 60
    timeRemaining = workDuration
    updateStatusButtonTitle() // show initial 25:00 immediately
    startTimer() // timer ticks but won't decrement until unpaused
    }

    func startTimer() {
        timer?.invalidate()
    // Use a manual timer added to .common run loop modes so it fires even when the menu is open (tracking mode)
    timer = Timer(timeInterval: 1, repeats: true) { _ in
            if !self.isPaused {
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                } else {
                    // Timer completed - send notification
                    self.sendNotification()
                    
                    // Switch session
                    self.isWorkSession.toggle()
                    self.timeRemaining = self.isWorkSession ? self.workDuration : self.breakDuration
                }
            }

            if let button = self.statusItem.button {
                switch self.displayMode {
                case .time:
                    let minutes = self.timeRemaining / 60
                    let seconds = self.timeRemaining % 60
                    button.title = String(format: "%02d:%02d", minutes, seconds)
                case .progress:
                    let total = self.isWorkSession ? self.workDuration : self.breakDuration
                    let progress = Double(total - self.timeRemaining) / Double(total)
                    button.title = String(format: "[%3.0f%%]", progress * 100)
                }
            }
        }
        if let t = timer {
            RunLoop.main.add(t, forMode: .common)
        }
    }
    
    private func sendNotification() {
        let finishedWork = isWorkSession // state BEFORE toggle (caller toggles after this)
        let content = UNMutableNotificationContent()
        if finishedWork {
            content.title = "Work Session Complete"
            content.body = "Time for a break (\(breakDuration/60) min)."
        } else {
            content.title = "Break Over"
            content.body = "Back to work (\(workDuration/60) min)."
        }
        content.sound = UNNotificationSound.default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Show notifications even if app is active
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    @objc func startWork() {
        isWorkSession = true
        timeRemaining = workDuration
    // Auto-resume when a new work session is explicitly started
    isPaused = false
    updateMenuDisplayState()
    updateStatusButtonTitle()
    }

    @objc func startBreak() {
        isWorkSession = false
        timeRemaining = breakDuration
    // Auto-resume when a break session is explicitly started
    isPaused = false
    updateMenuDisplayState()
    updateStatusButtonTitle()
    }

    @objc func togglePause() {
        isPaused.toggle()
        updateMenuDisplayState() // Update the menu to reflect pause state
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func openSettingsWindow() {
        // Reuse existing settings window if present
        if let existing = settingsWindowController, let existingWindow = existing.window {
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.orderFrontRegardless()
            if let tf = firstEditableTextField(in: existingWindow.contentView) {
                // Defer one cycle to ensure view layout finished
                DispatchQueue.main.async { existingWindow.makeFirstResponder(tf) }
            }
            return
        }

        // Create bindings (keep logic identical)
        let view = SettingsWindow(
            workMinutes: Binding(get: { self.workDuration / 60 }, set: { newVal in
                self.workDuration = max(1, newVal) * 60
                if self.isWorkSession {
                    self.timeRemaining = self.workDuration
                    self.updateStatusButtonTitle()
                }
            }),
            breakMinutes: Binding(get: { self.breakDuration / 60 }, set: { newVal in
                self.breakDuration = max(1, newVal) * 60
                if !self.isWorkSession {
                    self.timeRemaining = self.breakDuration
                    self.updateStatusButtonTitle()
                }
            }),
            displayMode: Binding(get: { self.displayMode }, set: { newMode in
                self.displayMode = newMode
                self.updateStatusButtonTitle()
            }),
            isPaused: Binding(get: { self.isPaused }, set: { val in
                self.isPaused = val
                self.updateMenuDisplayState()
            })
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Timer Settings"
        window.styleMask = [.titled, .closable]
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false

        // Try to position near the status bar item; fallback to center
        if let button = statusItem.button, let buttonWindow = button.window, let screen = buttonWindow.screen {
            let buttonFrameOnScreen = buttonWindow.frame
            let desiredSize = NSSize(width: 340, height: 230)
            var x = buttonFrameOnScreen.midX - desiredSize.width / 2
            var y = buttonFrameOnScreen.minY - desiredSize.height - 8
            let visible = screen.visibleFrame
            x = max(visible.minX + 12, min(x, visible.maxX - desiredSize.width - 12))
            y = max(visible.minY + 12, min(y, visible.maxY - desiredSize.height - 12))
            window.setFrame(NSRect(x: x, y: y, width: desiredSize.width, height: desiredSize.height), display: false)
        } else {
            window.center()
        }

        let controller = NSWindowController(window: window)
        settingsWindowController = controller

        // Activate app & show window immediately (menu will close automatically afterwards)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Make first responder next runloop cycle only (no arbitrary delay)
        DispatchQueue.main.async(qos: .userInteractive) { [weak self, weak window] in
            guard let self, let window else { return }
            if let tf = self.firstEditableTextField(in: window.contentView) {
                window.makeFirstResponder(tf)
            }
        }

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.settingsWindowController = nil
        }
    }

    private func firstEditableTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let tf = view as? NSTextField, tf.isEditable, tf.isEnabled, tf.acceptsFirstResponder { return tf }
        for sub in view.subviews {
            if let found = firstEditableTextField(in: sub) { return found }
        }
        return nil
    }

    @objc func setDisplayTime() {
        displayMode = .time
    updateMenuDisplayState()
    updateStatusButtonTitle()
    }

    @objc func setDisplayProgress() {
        displayMode = .progress
    updateMenuDisplayState()
    updateStatusButtonTitle()
    }
    
    // Removed inline confirm (settings handled in separate window)
    
    private func showConfirmationNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Timer Settings Updated"
        content.body = "Work: \(workDuration/60)min, Break: \(breakDuration/60)min"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "settings-confirm", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Legacy inline editing methods removed
    
    private func updateMenuDisplayState() {
        // Update the menu state and pause/resume text
        if let menu = statusItem.menu {
            // Update pause/resume button text and icon
            for item in menu.items {
                if item.action == #selector(togglePause) {
                    item.title = isPaused ? "Resume" : "Pause"
                    item.toolTip = isPaused ? "Resume the timer" : "Pause the timer"
                }
            }
            
            // (No display mode items in menu now; handled in window)
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        
        // Style main menu items with simple text
        let startWorkItem = NSMenuItem(title: "Start Work", action: #selector(startWork), keyEquivalent: "w")
        startWorkItem.toolTip = "Begin a work session"
        menu.addItem(startWorkItem)
        
        let startBreakItem = NSMenuItem(title: "Start Break", action: #selector(startBreak), keyEquivalent: "b")
        startBreakItem.toolTip = "Begin a break session"
        menu.addItem(startBreakItem)
        
    let pauseItem = NSMenuItem(title: isPaused ? "Resume" : "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.toolTip = isPaused ? "Resume the timer" : "Pause the timer"
        menu.addItem(pauseItem)
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        
        // Styled quit item
    let quitItem = NSMenuItem(title: "Quit Timer", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.toolTip = "Close the Timer application"
        if let attributedTitle = NSMutableAttributedString(string: quitItem.title) as NSMutableAttributedString? {
            attributedTitle.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: attributedTitle.length))
            quitItem.attributedTitle = attributedTitle
        }
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // Immediate status bar button title refresh (avoids waiting for next tick)
    private func updateStatusButtonTitle() {
        guard let button = statusItem.button else { return }
        switch displayMode {
        case .time:
            let minutes = timeRemaining / 60
            let seconds = timeRemaining % 60
            button.title = String(format: "%02d:%02d", minutes, seconds)
        case .progress:
            let total = isWorkSession ? workDuration : breakDuration
            let progress = Double(total - timeRemaining) / Double(total)
            button.title = String(format: "[%3.0f%%]", progress * 100)
        }
    }
}
