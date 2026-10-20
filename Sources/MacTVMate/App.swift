import AppKit
import SwiftUI

@main
struct MacTVMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model: AppModel

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        let m = AppModel()
        _model = StateObject(wrappedValue: m)
    }

    var body: some Scene {
        WindowGroup("MacTVMate") {
            RootView()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("TV") {
                Button("Search…") { model.openSearch() }.keyboardShortcut("f", modifiers: [.command])
                Button(model.isFullScreen ? "Exit Full Screen" : "Watch Full Screen") { model.toggleFullScreen() }
                    .keyboardShortcut(.return, modifiers: [.command])
                Button("TV Guide") { model.showSettings = false; model.showGuide() }.keyboardShortcut("1", modifiers: [.command])
                Button("Favourites") { model.selectedGroup = ChannelGroup.favourites; model.showGuide() }.keyboardShortcut("d", modifiers: [.command])
                Button("Settings…") { model.showSettings = true }.keyboardShortcut(",", modifiers: [.command])
                Button("Movies") { model.showSettings = false; model.screen = .movies }.keyboardShortcut("2", modifiers: [.command])
                Button("Shows") { model.showSettings = false; model.screen = .shows }.keyboardShortcut("3", modifiers: [.command])
                Button("Recordings") { model.showSettings = false; model.screen = .recordings }.keyboardShortcut("4", modifiers: [.command])
                Button("My list") { model.showSettings = false; model.screen = .myList }.keyboardShortcut("5", modifiers: [.command])
                Button("Refresh Playlist & EPG") { Task { await model.reload(force: true) } }.keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Previous Channel") { model.playPrevious() }.keyboardShortcut(.delete, modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (swift run).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
