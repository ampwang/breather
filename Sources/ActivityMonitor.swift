import AppKit
import ApplicationServices

/// Counts global keystrokes and mouse clicks, and reports system idle time.
/// Keystroke counting needs Accessibility permission (System Settings → Privacy & Security → Accessibility).
/// Only *counts* are kept — which keys you press is never looked at or stored.
final class ActivityMonitor {
    var onKey: (() -> Void)?
    var onClick: (() -> Void)?
    private var monitors: [Any] = []

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Seconds since the last keyboard/mouse/trackpad event anywhere on the system. Needs no permission.
    static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func start() {
        stop()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: { [weak self] _ in
            self?.onKey?()
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            self?.onClick?()
        }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
