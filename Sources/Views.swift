import AppKit
import ServiceManagement
import SwiftUI

struct MenuLabel: View {
    @ObservedObject var s: BreakScheduler
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: s.isPaused ? "pause.circle" : (s.trusted ? "hand.raised" : "exclamationmark.triangle"))
            Text(s.menuBarText).monospacedDigit()
        }
    }
}

struct MenuView: View {
    @EnvironmentObject var s: BreakScheduler
    @AppStorage(Prefs.K.microEnabled) private var microEnabled = true
    @AppStorage(Prefs.K.restEnabled) private var restEnabled = true
    @AppStorage(Prefs.K.keyLimit) private var keyLimit = 4000
    @AppStorage(Prefs.K.clickLimit) private var clickLimit = 1500

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breather").font(.headline)

            if !s.trusted {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Allow Accessibility so Breather can count keys and clicks.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Accessibility Settings") { ActivityMonitor.openAccessibilitySettings() }
                }
            }

            if let until = s.pausedUntil, s.isPaused {
                Label("Paused until \(until.formatted(date: .omitted, time: .shortened))", systemImage: "pause.circle")
            } else if let p = s.postponed {
                Label("\(p.kind.title) postponed, \(formatClock(p.until.timeIntervalSinceNow)) left",
                      systemImage: "clock.arrow.circlepath")
            }

            if microEnabled {
                ProgressRow(title: "Next micro-break",
                            detail: "in \(formatHM(s.microRemaining + 59))",
                            progress: s.microProgress)
            }
            if restEnabled {
                ProgressRow(title: "Next rest break",
                            detail: "in \(formatHM(s.restRemaining + 59))",
                            progress: s.restProgress)
                Text("Keys \(s.keysSinceRest)\(keyLimit > 0 ? "/\(keyLimit)" : "") · Clicks \(s.clicksSinceRest)\(clickLimit > 0 ? "/\(clickLimit)" : "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Text("Today").font(.subheadline.bold())
            HStack {
                StatView(label: "Active", value: formatHM(s.activeToday))
                StatView(label: "Keys", value: "\(s.keysToday)")
                StatView(label: "Clicks", value: "\(s.clicksToday)")
            }

            Divider()

            HStack {
                Button("Micro-break now") { s.takeBreakNow(.micro) }
                Button("Rest now") { s.takeBreakNow(.rest) }
            }
            if s.isPaused {
                Button("Resume") { s.resume() }
            } else {
                Menu("Pause for…") {
                    Button("30 minutes") { s.pause(minutes: 30) }
                    Button("1 hour") { s.pause(minutes: 60) }
                    Button("2 hours") { s.pause(minutes: 120) }
                }
                .fixedSize()
            }

            HStack {
                Button("Settings…") { SettingsWindow.shared.show() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

private struct ProgressRow: View {
    let title: String
    let detail: String
    let progress: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(detail).foregroundColor(.secondary).monospacedDigit()
            }
            .font(.callout)
            ProgressView(value: progress)
        }
    }
}

private struct StatView: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(value).font(.title3.monospacedDigit())
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings

@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Breather Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.K.microEnabled) private var microEnabled = true
    @AppStorage(Prefs.K.microInterval) private var microInterval = 10
    @AppStorage(Prefs.K.microDuration) private var microDuration = 20
    @AppStorage(Prefs.K.restEnabled) private var restEnabled = true
    @AppStorage(Prefs.K.restInterval) private var restInterval = 50
    @AppStorage(Prefs.K.restDuration) private var restDuration = 5
    @AppStorage(Prefs.K.keyLimit) private var keyLimit = 4000
    @AppStorage(Prefs.K.clickLimit) private var clickLimit = 1500
    @AppStorage(Prefs.K.idleThreshold) private var idleThreshold = 30
    @AppStorage(Prefs.K.warningSeconds) private var warningSeconds = 30
    @AppStorage(Prefs.K.maxPostpones) private var maxPostpones = 2
    @AppStorage(Prefs.K.postponeMinutes) private var postponeMinutes = 5
    @AppStorage(Prefs.K.allowSkip) private var allowSkip = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Micro-breaks (short and frequent)") {
                Toggle("Enabled", isOn: $microEnabled)
                Stepper("Every \(microInterval) min of activity", value: $microInterval, in: 3...60)
                Stepper("Lasts \(microDuration) sec", value: $microDuration, in: 10...180, step: 5)
            }
            Section("Rest breaks (longer, get up and move)") {
                Toggle("Enabled", isOn: $restEnabled)
                Stepper("Every \(restInterval) min of activity", value: $restInterval, in: 10...180, step: 5)
                Stepper("Lasts \(restDuration) min", value: $restDuration, in: 1...30)
                Stepper(keyLimit == 0 ? "Keystroke limit: off" : "…or after \(keyLimit) keystrokes",
                        value: $keyLimit, in: 0...30000, step: 500)
                Stepper(clickLimit == 0 ? "Click limit: off" : "…or after \(clickLimit) mouse clicks",
                        value: $clickLimit, in: 0...10000, step: 250)
            }
            Section("Behaviour") {
                Stepper(warningSeconds == 0 ? "No warning before a break" : "Warn \(warningSeconds) sec before a break",
                        value: $warningSeconds, in: 0...120, step: 5)
                Stepper("Allow \(maxPostpones) postpone\(maxPostpones == 1 ? "" : "s") per break",
                        value: $maxPostpones, in: 0...5)
                Stepper("Postpone by \(postponeMinutes) min", value: $postponeMinutes, in: 1...30)
                Toggle("Allow skipping breaks", isOn: $allowSkip)
                Stepper("Treat \(idleThreshold) sec without input as idle", value: $idleThreshold, in: 10...120, step: 5)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundColor(.red)
                }
            }
            Section {
                Text("Being away from the keyboard and mouse for a full break length counts as a break, and the timer resets.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
    }
}
