import SwiftUI

@main
struct BreatherApp: App {
    @StateObject private var scheduler = BreakScheduler()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(scheduler)
        } label: {
            MenuLabel(s: scheduler)
        }
        .menuBarExtraStyle(.window)
    }
}
