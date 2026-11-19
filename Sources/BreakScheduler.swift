import AppKit
import SwiftUI

enum BreakKind: String {
    case micro, rest
    var title: String { self == .micro ? "Micro-break" : "Rest break" }
    var duration: TimeInterval { self == .micro ? Prefs.microDuration : Prefs.restDuration }
}

enum Phase: Equatable {
    case working
    case warning(BreakKind, until: Date)
    case onBreak(BreakKind, until: Date)
}

struct Postponed: Equatable {
    let kind: BreakKind
    let until: Date
}

/// The brain: ticks once a second, accumulates active time / keys / clicks,
/// detects natural breaks (you walked away), and triggers warning → lock-screen breaks.
@MainActor
final class BreakScheduler: ObservableObject {
    @Published private(set) var phase: Phase = .working
    @Published private(set) var microActive: TimeInterval = 0
    @Published private(set) var restActive: TimeInterval = 0
    @Published private(set) var keysSinceRest = 0
    @Published private(set) var clicksSinceRest = 0
    @Published private(set) var keysToday = 0
    @Published private(set) var clicksToday = 0
    @Published private(set) var activeToday: TimeInterval = 0
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var postponed: Postponed?
    @Published private(set) var postponesUsed = 0
    @Published private(set) var trusted = ActivityMonitor.isTrusted

    private let monitor = ActivityMonitor()
    private let overlay: OverlayController
    private let hud: WarningHUD
    private var timer: Timer?
    private var tickCount = 0
    private var statsDay: String

    init() {
        overlay = OverlayController()
        hud = WarningHUD()
        statsDay = Self.dayString()
        Prefs.registerDefaults()
        loadStats()

        monitor.onKey = { [weak self] in Task { @MainActor in self?.recordKey() } }
        monitor.onClick = { [weak self] in Task { @MainActor in self?.recordClick() } }
        monitor.start()
        if !trusted { ActivityMonitor.requestTrust() }

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.saveStats() }
        }
    }

    // MARK: - Derived state for the UI

    var isPaused: Bool { pausedUntil.map { $0 > Date() } ?? false }

    var microRemaining: TimeInterval { max(0, Prefs.microInterval - microActive) }
    var restRemaining: TimeInterval { max(0, Prefs.restInterval - restActive) }

    /// 0...1 — whichever rest trigger (time, keys, clicks) is closest to firing.
    var restProgress: Double {
        var p = Prefs.restInterval > 0 ? restActive / Prefs.restInterval : 0
        if Prefs.keyLimit > 0 { p = max(p, Double(keysSinceRest) / Double(Prefs.keyLimit)) }
        if Prefs.clickLimit > 0 { p = max(p, Double(clicksSinceRest) / Double(Prefs.clickLimit)) }
        return min(1, p)
    }

    var microProgress: Double {
        Prefs.microInterval > 0 ? min(1, microActive / Prefs.microInterval) : 0
    }

    var postponesLeft: Int { max(0, Prefs.maxPostpones - postponesUsed) }

    var menuBarText: String {
        switch phase {
        case .onBreak: return "break"
        case .warning(_, let until): return formatClock(until.timeIntervalSinceNow)
        case .working: break
        }
        if isPaused { return "" }
        if let p = postponed { return "\(Int((p.until.timeIntervalSinceNow / 60).rounded(.up)))m" }
        var next: TimeInterval?
        if Prefs.microEnabled { next = microRemaining }
        if Prefs.restEnabled { next = min(next ?? .infinity, restRemaining) }
        guard let n = next else { return "" }
        return "\(Int((n / 60).rounded(.up)))m"
    }

    // MARK: - Actions

    func takeBreakNow(_ kind: BreakKind) {
        guard case .working = phase else { return }
        postponed = nil
        startBreak(kind)
    }

    func postpone() {
        guard postponesLeft > 0 else { return }
        let kind: BreakKind
        switch phase {
        case .warning(let k, _), .onBreak(let k, _): kind = k
        case .working: return
        }
        postponesUsed += 1
        postponed = Postponed(kind: kind, until: Date().addingTimeInterval(Prefs.postponeDuration))
        overlay.hide()
        hud.hide()
        phase = .working
    }

    func skip() {
        guard Prefs.allowSkip else { return }
        switch phase {
        case .warning(let k, _), .onBreak(let k, _): finishBreak(k, chime: false)
        case .working: break
        }
    }

    func pause(minutes: Int) {
        hud.hide()
        if case .warning = phase { phase = .working }
        guard case .working = phase else { return }
        pausedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func resume() { pausedUntil = nil }

    // MARK: - Engine

    private func recordKey() { keysSinceRest += 1; keysToday += 1 }
    private func recordClick() { clicksSinceRest += 1; clicksToday += 1 }

    private func tick() {
        let now = Date()
        tickCount += 1
        rollDayIfNeeded()
        if tickCount % 5 == 0 { checkTrust() }
        if tickCount % 30 == 0 { saveStats() }

        switch phase {
        case .onBreak(let kind, let until):
            if now >= until { finishBreak(kind, chime: true) }
            return
        case .warning(let kind, let until):
            if now >= until { startBreak(kind) }
            return
        case .working:
            break
        }

        if let p = pausedUntil {
            if now < p { return }
            pausedUntil = nil
        }

        // Natural breaks: if you were away from keyboard & mouse long enough, that counts as a break.
        let idle = ActivityMonitor.idleSeconds
        if idle >= Prefs.restDuration {
            resetMicro(); resetRest()
            postponed = nil; postponesUsed = 0
        } else if idle >= Prefs.microDuration {
            resetMicro()
            if postponed?.kind == .micro { postponed = nil; postponesUsed = 0 }
        }

        if idle < Prefs.idleThreshold {
            microActive += 1
            restActive += 1
            activeToday += 1
        }

        let due = dueBreak()
        if let p = postponed {
            if due == .rest && p.kind == .micro { beginWarning(.rest) }   // escalate
            else if now >= p.until { beginWarning(p.kind) }
            return
        }
        if let due { beginWarning(due) }
    }

    private func dueBreak() -> BreakKind? {
        if Prefs.restEnabled {
            if restActive >= Prefs.restInterval { return .rest }
            if Prefs.keyLimit > 0 && keysSinceRest >= Prefs.keyLimit { return .rest }
            if Prefs.clickLimit > 0 && clicksSinceRest >= Prefs.clickLimit { return .rest }
        }
        if Prefs.microEnabled && microActive >= Prefs.microInterval { return .micro }
        return nil
    }

    private func beginWarning(_ kind: BreakKind) {
        postponed = nil
        guard Prefs.warningSeconds > 0 else { startBreak(kind); return }
        let until = Date().addingTimeInterval(Prefs.warningSeconds)
        phase = .warning(kind, until: until)
        hud.show(kind: kind, until: until, postponesLeft: postponesLeft,
                 onPostpone: { [weak self] in self?.postpone() },
                 onStart: { [weak self] in self?.startBreak(kind) })
    }

    private func startBreak(_ kind: BreakKind) {
        hud.hide()
        let duration = kind.duration
        let until = Date().addingTimeInterval(duration)
        phase = .onBreak(kind, until: until)
        overlay.show(BreakView(
            kind: kind,
            until: until,
            total: duration,
            postponesLeft: postponesLeft,
            postponeMinutes: Int(Prefs.postponeDuration / 60),
            allowSkip: Prefs.allowSkip,
            tip: Tips.random(for: kind),
            onPostpone: { [weak self] in self?.postpone() },
            onSkip: { [weak self] in self?.skip() }
        ))
    }

    private func finishBreak(_ kind: BreakKind, chime: Bool) {
        overlay.hide()
        hud.hide()
        resetMicro()
        if kind == .rest { resetRest() }
        postponed = nil
        postponesUsed = 0
        phase = .working
        if chime { NSSound(named: "Glass")?.play() }
    }

    private func resetMicro() { microActive = 0 }
    private func resetRest() { restActive = 0; keysSinceRest = 0; clicksSinceRest = 0 }

    private func checkTrust() {
        let t = ActivityMonitor.isTrusted
        if t != trusted {
            trusted = t
            if t { monitor.start() }   // monitors created before permission was granted get no key events
        }
    }

    // MARK: - Daily stats (persisted so a restart doesn't zero them)

    nonisolated private static func dayString() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func rollDayIfNeeded() {
        let today = Self.dayString()
        guard today != statsDay else { return }
        statsDay = today
        keysToday = 0; clicksToday = 0; activeToday = 0
        saveStats()
    }

    private func loadStats() {
        let d = Prefs.d
        guard d.string(forKey: "statsDay") == statsDay else { return }
        keysToday = d.integer(forKey: "keysToday")
        clicksToday = d.integer(forKey: "clicksToday")
        activeToday = d.double(forKey: "activeToday")
    }

    private func saveStats() {
        let d = Prefs.d
        d.set(statsDay, forKey: "statsDay")
        d.set(keysToday, forKey: "keysToday")
        d.set(clicksToday, forKey: "clicksToday")
        d.set(activeToday, forKey: "activeToday")
    }
}

enum Tips {
    static let micro = [
        "Let your hands hang loose by your sides and gently shake them out.",
        "Rest your hands in your lap, palms up. Relax your shoulders.",
        "Slowly open your hands wide, then make a soft fist. Repeat 5 times.",
        "Look at something far away and blink a few times.",
        "Drop your shoulders away from your ears and take three slow breaths.",
    ]
    static let rest = [
        "Stand up, walk around, and get a glass of water.",
        "Gently stretch your forearm: arm out, palm up, ease the fingers back with the other hand for 15 s. Swap sides. Stop if it hurts.",
        "Roll your shoulders backwards 10 times, then let your arms hang loose.",
        "Step away from the desk. Look out of a window for a minute.",
        "Slowly turn your head left and right, then tilt each ear toward your shoulder.",
    ]
    static func random(for kind: BreakKind) -> String {
        (kind == .micro ? micro : rest).randomElement() ?? ""
    }
}
