import Cocoa
import SwiftUI
import UserNotifications

// MARK: - Productivity Timer (Menu Bar)
// This file hosts the core logic for a minimal macOS menu bar (status bar) Pomodoro‑style timer.
// The app intentionally has no main window; user interaction happens through:
// 1. The status bar menu (start work / break, pause/resume, settings, quit)
// 2. A lightweight SwiftUI settings popover-like window (see `SettingsWindow`)
// 3. Local user notifications (optional) for session transitions & 1‑minute warnings
//
// Design goals:
// - Zero visual clutter (text only in status bar; no icon, no dock presence)
// - Immediate legibility: either remaining time (MM:SS) or progress percentage
// - Persist user preferences across launches using UserDefaults
// - Graceful handling when the menu is open (timer still ticks via RunLoop.common)
// - No background agents or launch daemons; pure NSStatusItem lifecycle
//
// NOTE: Logic prefers clarity over micro‑optimizations. Durations are kept as whole seconds (Int).

// Moved out of AppDelegate so other files (e.g., SettingsWindow.swift) can reference it
// MARK: Display Mode Options
/// Controls what is rendered inside the status bar button:
///  - `.time`: Remaining minutes & seconds (e.g., 14:07)
///  - `.progress`: Elapsed percent of the current session (e.g., [ 42%])
enum DisplayMode: Hashable { case time; case progress }

// MARK: - AppDelegate
/// Acts as the central orchestrator: sets up the status item, manages the timer,
/// owns mutable session state, presents settings, and routes notification events.
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    // MARK: Core runtime state
    var statusItem: NSStatusItem!              // The single menu bar item
    var timer: Timer?                          // Repeating 1s driver (added manually to run loop)
    var isWorkSession = true                   // true = work, false = break
    var timeRemaining = 25 * 60                // Seconds left in the active session
    var isPaused = true                        // Starts paused so user explicitly begins

    // Display mode and durations
    // MARK: User preferences (mutable & persisted)
    var displayMode: DisplayMode = .time       // Time vs % progress
    var workDuration: Int = 25 * 60            // Work session length (seconds)
    var breakDuration: Int = 5 * 60            // Break session length (seconds)
    var settingsWindowController: NSWindowController? // Retain settings window instance
    // Notification preferences
    // MARK: Notification flags
    var notificationsEnabled: Bool = true
    var oneMinuteWarningEnabled: Bool = true
    private var didSendOneMinuteWarning: Bool = false // Debounce so 1‑minute warning fires once
    private let defaults = UserDefaults.standard
    private let prefWorkMinutesKey = "workMinutes"
    private let prefBreakMinutesKey = "breakMinutes"
    private let prefDisplayModeKey = "displayMode"
    private let prefNotificationsEnabledKey = "notificationsEnabled"
    private let prefOneMinuteWarningKey = "oneMinuteWarningEnabled"
    private let prefPausedKey = "pausedState"
    // Debug logging removed for production build

    // DisplayMode enum now top-level

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory app: no dock icon, still allowed to present windows
        NSApp.setActivationPolicy(.accessory)
        
    // Restore persisted configuration *before* building the menu/UI
        loadPreferences()

    // Ask once for notification permission. Delegate ensures banners appear while active.
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        
    // Create the status bar item (text only; no template image)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
    buildMenu()
    if workDuration <= 0 { workDuration = 25 * 60 }
    if breakDuration <= 0 { breakDuration = 5 * 60 }
    timeRemaining = isWorkSession ? workDuration : breakDuration
    updateStatusButtonTitle() // Show initial e.g. 25:00 instantly
    startTimer()              // Schedule ticking (logic gated by isPaused)
    }

    /// Create & register (or restart) the 1‑second heartbeat timer.
    /// Added in `.common` modes so it continues while the status menu is open.
    func startTimer() {
        timer?.invalidate()
        // Manual scheduling vs. `scheduledTimer` gives explicit run loop mode control
    timer = Timer(timeInterval: 1, repeats: true) { _ in
            if !self.isPaused {
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                    // Fire a single optional 60‑second remaining notification
                    if self.oneMinuteWarningEnabled && self.notificationsEnabled && self.timeRemaining == 60 && !self.didSendOneMinuteWarning {
                        self.didSendOneMinuteWarning = true
                        self.sendNotification(title: self.isWorkSession ? "Work Almost Done" : "Break Ending Soon", body: "1 minute remaining")
                    }
                } else {
                    // Timer completed - send notification
                    if self.notificationsEnabled {
                        self.sendCompletionNotification()
                    }
                    
                    // Switch session
                    self.isWorkSession.toggle()
                    self.timeRemaining = self.isWorkSession ? self.workDuration : self.breakDuration
                    self.didSendOneMinuteWarning = false
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
    if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }
    
    /// Session boundary notification (work finished -> suggest break; break finished -> back to work).
    private func sendCompletionNotification() {
        let finishedWork = isWorkSession // Capture current role before external toggle
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

    /// Generic one‑off banner (currently used for the 1‑minute warning).
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
    }

    // Show notifications even if app is active
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Respect user toggle: drop notifications when globally disabled
        if !notificationsEnabled {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    /// Explicitly begin a fresh work session (auto‑resumes if paused).
    @objc func startWork() {
        isWorkSession = true
        timeRemaining = workDuration
        isPaused = false
    didSendOneMinuteWarning = false
    updateMenuDisplayState()
    updateStatusButtonTitle()
    savePreferences()
    }

    /// Explicitly begin a fresh break session (auto‑resumes if paused).
    @objc func startBreak() {
        isWorkSession = false
        timeRemaining = breakDuration
        isPaused = false
    didSendOneMinuteWarning = false
    updateMenuDisplayState()
    updateStatusButtonTitle()
    savePreferences()
    }

    /// Toggle between paused and active ticking states.
    @objc func togglePause() {
        isPaused.toggle()
        updateMenuDisplayState() // Update the menu to reflect pause state
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    /// Present (or re‑focus) the SwiftUI settings window.
    @objc func openSettingsWindow() {
        // Reuse existing settings window if present
        if let existing = settingsWindowController, let existingWindow = existing.window {
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
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
                self.savePreferences()
            }),
            breakMinutes: Binding(get: { self.breakDuration / 60 }, set: { newVal in
                self.breakDuration = max(1, newVal) * 60
                if !self.isWorkSession {
                    self.timeRemaining = self.breakDuration
                    self.updateStatusButtonTitle()
                }
                self.savePreferences()
            }),
            displayMode: Binding(get: { self.displayMode }, set: { newMode in
                self.displayMode = newMode
                self.updateStatusButtonTitle()
                self.savePreferences()
            }),
            isPaused: Binding(get: { self.isPaused }, set: { val in
                self.isPaused = val
                self.updateMenuDisplayState()
                self.savePreferences()
            }),
            notificationsEnabled: Binding(get: { self.notificationsEnabled }, set: { newVal in
                self.notificationsEnabled = newVal
                if !newVal {
                    // Cancel any pending/delivered notifications when turning off
                    let center = UNUserNotificationCenter.current()
                    center.removeAllPendingNotificationRequests()
                    center.removeAllDeliveredNotifications()
                    // Also reset one-minute warning flag so it can fire again if re-enabled mid-session
                    self.didSendOneMinuteWarning = false
                }
                self.savePreferences()
            }),
            oneMinuteWarningEnabled: Binding(get: { self.oneMinuteWarningEnabled }, set: { newVal in
                let previous = self.oneMinuteWarningEnabled
                self.oneMinuteWarningEnabled = newVal
                if !newVal {
                    // Mark as already sent so it won't trigger at 60s this session
                    self.didSendOneMinuteWarning = true
                } else if previous == false { // re-enabled
                    // Allow it again if threshold not yet reached
                    if self.timeRemaining > 60 { self.didSendOneMinuteWarning = false }
                }
                self.savePreferences()
            })
        )

    let hosting = NSHostingController(rootView: view) // Bridge SwiftUI into AppKit window
        let window = NSWindow(contentViewController: hosting)
        window.title = "Timer Settings"
        window.styleMask = [.titled, .closable]
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false

        // Try to position near the status bar item; fallback to center
        if let button = statusItem.button, let buttonWindow = button.window, let screen = buttonWindow.screen {
            let buttonFrameOnScreen = buttonWindow.frame
            let desiredSize = NSSize(width: 340, height: 260)
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
    private func savePreferences() {
        defaults.set(workDuration / 60, forKey: prefWorkMinutesKey)
        defaults.set(breakDuration / 60, forKey: prefBreakMinutesKey)
        defaults.set(displayMode == .time ? "time" : "progress", forKey: prefDisplayModeKey)
        defaults.set(notificationsEnabled, forKey: prefNotificationsEnabledKey)
        defaults.set(oneMinuteWarningEnabled, forKey: prefOneMinuteWarningKey)
        defaults.set(isPaused, forKey: prefPausedKey)
    }

    private func loadPreferences() {
        if let storedWork = defaults.object(forKey: prefWorkMinutesKey) as? Int { workDuration = storedWork * 60 }
        if let storedBreak = defaults.object(forKey: prefBreakMinutesKey) as? Int { breakDuration = storedBreak * 60 }
        if let mode = defaults.string(forKey: prefDisplayModeKey) { displayMode = (mode == "progress") ? .progress : .time }
        if defaults.object(forKey: prefNotificationsEnabledKey) != nil { notificationsEnabled = defaults.bool(forKey: prefNotificationsEnabledKey) }
        if defaults.object(forKey: prefOneMinuteWarningKey) != nil { oneMinuteWarningEnabled = defaults.bool(forKey: prefOneMinuteWarningKey) }
        if defaults.object(forKey: prefPausedKey) != nil { isPaused = defaults.bool(forKey: prefPausedKey) }
    }

    /// Depth‑first search for the first editable text field (used to focus on open).
    private func firstEditableTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let tf = view as? NSTextField, tf.isEditable, tf.isEnabled, tf.acceptsFirstResponder { return tf }
        for sub in view.subviews {
            if let found = firstEditableTextField(in: sub) { return found }
        }
        return nil
    }

    // Legacy menu toggles retained for potential future use; currently unused externally.
    @objc func setDisplayTime()  { displayMode = .time;      updateMenuDisplayState(); updateStatusButtonTitle() }
    @objc func setDisplayProgress() { displayMode = .progress; updateMenuDisplayState(); updateStatusButtonTitle() }
    
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
    
    /// Refresh dynamic menu item titles/tooltips (e.g., Pause vs Resume).
    private func updateMenuDisplayState() {
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

    /// Construct the status bar dropdown menu (idempotent rebuild safe).
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
    /// Immediate recompute & assign status button text; avoids wait for next tick.
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
