import SwiftUI

// MARK: - Application Entry Point
// Uses the SwiftUI lifecycle only as a thin wrapper to host an `NSStatusItem` app.
// There is no persistent main window; the singular Scene is a `Settings` scene
// with an empty body to satisfy the App protocol. All logic lives in `AppDelegate`.

@main
struct TimerBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {} // No main window, only settings if needed
    }
}
