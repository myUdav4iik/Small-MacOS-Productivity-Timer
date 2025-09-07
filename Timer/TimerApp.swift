import SwiftUI

@main
struct TimerBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {} // No main window, only settings if needed
    }
}
