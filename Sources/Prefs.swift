import Foundation

/// All user settings live in UserDefaults. SettingsView binds to the same keys via @AppStorage.
enum Prefs {
    static let d = UserDefaults.standard

    enum K {
        static let microEnabled = "microEnabled"
        static let microInterval = "microIntervalMin"
        static let microDuration = "microDurationSec"
        static let restEnabled = "restEnabled"
        static let restInterval = "restIntervalMin"
        static let restDuration = "restDurationMin"
        static let keyLimit = "keystrokeLimit"
        static let clickLimit = "clickLimit"
        static let idleThreshold = "idleThresholdSec"
        static let warningSeconds = "warningSec"
        static let maxPostpones = "maxPostpones"
        static let postponeMinutes = "postponeMin"
        static let allowSkip = "allowSkip"
    }

    /// Keep these in sync with the @AppStorage defaults in SettingsView / MenuView.
    static let defaults: [String: Any] = [
        K.microEnabled: true,
        K.microInterval: 10,
        K.microDuration: 20,
        K.restEnabled: true,
        K.restInterval: 50,
        K.restDuration: 5,
        K.keyLimit: 4000,
        K.clickLimit: 1500,
        K.idleThreshold: 30,
        K.warningSeconds: 30,
        K.maxPostpones: 2,
        K.postponeMinutes: 5,
        K.allowSkip: false,
    ]

    static func registerDefaults() { d.register(defaults: defaults) }

    static var microEnabled: Bool { d.bool(forKey: K.microEnabled) }
    static var microInterval: TimeInterval { TimeInterval(d.integer(forKey: K.microInterval)) * 60 }
    static var microDuration: TimeInterval { TimeInterval(d.integer(forKey: K.microDuration)) }

    static var restEnabled: Bool { d.bool(forKey: K.restEnabled) }
    static var restInterval: TimeInterval { TimeInterval(d.integer(forKey: K.restInterval)) * 60 }
    static var restDuration: TimeInterval { TimeInterval(d.integer(forKey: K.restDuration)) * 60 }

    /// 0 = off
    static var keyLimit: Int { d.integer(forKey: K.keyLimit) }
    static var clickLimit: Int { d.integer(forKey: K.clickLimit) }

    static var idleThreshold: TimeInterval { TimeInterval(d.integer(forKey: K.idleThreshold)) }
    static var warningSeconds: TimeInterval { TimeInterval(d.integer(forKey: K.warningSeconds)) }
    static var maxPostpones: Int { d.integer(forKey: K.maxPostpones) }
    static var postponeDuration: TimeInterval { TimeInterval(d.integer(forKey: K.postponeMinutes)) * 60 }
    static var allowSkip: Bool { d.bool(forKey: K.allowSkip) }
}

func formatClock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t.rounded(.up)))
    return String(format: "%d:%02d", s / 60, s % 60)
}

func formatHM(_ t: TimeInterval) -> String {
    let m = Int(t) / 60
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}
