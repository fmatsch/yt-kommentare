import SwiftUI
import AppKit

@main
struct YTKommentareApp: App {
    @StateObject private var auth: AuthManager
    @StateObject private var store: CommentStore

    init() {
        let auth = AuthManager()
        _auth = StateObject(wrappedValue: auth)
        _store = StateObject(wrappedValue: CommentStore(auth: auth))
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("YT Kommentare") {
            ContentView()
                .environmentObject(auth)
                .environmentObject(store)
                .frame(minWidth: 1000, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Jetzt abrufen") { Task { await store.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
