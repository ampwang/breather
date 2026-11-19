import AppKit
import SwiftUI

private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Full-screen "lock" shown on every display during a break.
@MainActor
final class OverlayController {
    private var windows: [NSWindow] = []

    func show<V: View>(_ view: V) {
        hide(restoreFocus: false)
        for screen in NSScreen.screens {
            let w = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = false
            w.backgroundColor = .clear
            w.contentView = NSHostingView(rootView: view)
            w.setFrame(screen.frame, display: true)
            w.makeKeyAndOrderFront(nil)
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        // Hide Dock + menu bar and block Cmd-Tab while the break runs.
        // Force Quit (Cmd-Opt-Esc) is deliberately left working as an escape hatch.
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
    }

    func hide(restoreFocus: Bool = true) {
        guard !windows.isEmpty else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSApp.presentationOptions = []
        if restoreFocus { NSApp.hide(nil) }   // hand focus back to the app you were using
    }
}

struct BreakView: View {
    let kind: BreakKind
    let until: Date
    let total: TimeInterval
    let postponesLeft: Int
    let postponeMinutes: Int
    let allowSkip: Bool
    let tip: String
    let onPostpone: @MainActor () -> Void
    let onSkip: @MainActor () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: kind == .micro ? "hand.raised.fill" : "figure.walk")
                    .font(.system(size: 56))
                    .foregroundColor(.white.opacity(0.9))
                Text(kind.title)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.white)
                Text(tip)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)

                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let remaining = max(0, until.timeIntervalSince(ctx.date))
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.15), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: CGFloat(total > 0 ? remaining / total : 0))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(formatClock(remaining))
                            .font(.system(size: 54, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                    .frame(width: 220, height: 220)
                }

                HStack(spacing: 16) {
                    if postponesLeft > 0 {
                        Button("Postpone \(postponeMinutes) min (\(postponesLeft) left)") { onPostpone() }
                    }
                    if allowSkip {
                        Button("Skip") { onSkip() }
                    }
                }
                .controlSize(.large)

                if postponesLeft == 0 && !allowSkip {
                    Text("No postpones left. Your hands will thank you.")
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(40)
        }
    }
}

/// Small floating heads-up in the top-right corner before a break starts,
/// so you can finish your sentence. Doesn't steal keyboard focus.
@MainActor
final class WarningHUD {
    private var panel: NSPanel?

    func show(kind: BreakKind, until: Date, postponesLeft: Int,
              onPostpone: @escaping @MainActor () -> Void,
              onStart: @escaping @MainActor () -> Void) {
        hide()
        let size = NSSize(width: 340, height: 92)
        let host = NSHostingView(rootView: WarningView(kind: kind, until: until, postponesLeft: postponesLeft,
                                                       onPostpone: onPostpone, onStart: onStart))
        host.frame = NSRect(origin: .zero, size: size)

        let p = KeyablePanel(contentRect: host.frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = host
        if let vf = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 16, y: vf.maxY - size.height - 16))
        }
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct WarningView: View {
    let kind: BreakKind
    let until: Date
    let postponesLeft: Int
    let onPostpone: @MainActor () -> Void
    let onStart: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                Label("\(kind.title) in \(formatClock(until.timeIntervalSince(ctx.date)))", systemImage: "hand.raised")
                    .font(.headline)
                    .monospacedDigit()
            }
            HStack {
                if postponesLeft > 0 {
                    Button("Postpone (\(postponesLeft) left)") { onPostpone() }
                }
                Spacer()
                Button("Start now") { onStart() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 340, height: 92)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
