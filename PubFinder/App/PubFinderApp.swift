import SwiftUI

@main
struct PubFinderApp: App {
    @StateObject private var brew = HomebrewService()
    @StateObject private var categories = CategoryService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(brew)
                .environmentObject(categories)
                .frame(minWidth: 1040, minHeight: 600)
                .task { await categories.refreshFromRemote() }
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    NotificationCenter.default.post(name: .brewRefreshRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let brewRefreshRequested = Notification.Name("brewRefreshRequested")
}
