import SwiftUI
import AppKit

struct SettingsWindow: View {
    @Binding var workMinutes: Int
    @Binding var breakMinutes: Int
    @Binding var displayMode: DisplayMode
    @Binding var isPaused: Bool
    @Binding var notificationsEnabled: Bool
    @Binding var oneMinuteWarningEnabled: Bool

    @State private var tempWork: String = ""
    @State private var tempBreak: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Timer Settings")
                .font(.title2).bold()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Work (min)")
                    Spacer()
                    TextField("25", text: Binding(
                        get: { tempWork },
                        set: { newVal in
                            tempWork = newVal.filter { $0.isNumber }
                            if let v = Int(tempWork), v > 0 { workMinutes = v }
                        })
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Break (min)")
                    Spacer()
                    TextField("5", text: Binding(
                        get: { tempBreak },
                        set: { newVal in
                            tempBreak = newVal.filter { $0.isNumber }
                            if let v = Int(tempBreak), v > 0 { breakMinutes = v }
                        })
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                }
                VStack(alignment: .leading) {
                    Text("Display Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Display Mode", selection: $displayMode) {
                        Text("Time").tag(DisplayMode.time)
                        Text("Progress").tag(DisplayMode.progress)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                
                Divider().padding(.vertical, 4)
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                Toggle("1-Minute Warning", isOn: $oneMinuteWarningEnabled)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Close") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
    .frame(minWidth: 380, minHeight: 380)
        .onAppear {
            tempWork = String(workMinutes)
            tempBreak = String(breakMinutes)
        }
    }
}

