import AppKit
import SwiftUI

@main
struct TotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Tota", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.worker)
                .environmentObject(model.player)
                .frame(minWidth: 1180, minHeight: 680)
                .onAppear { model.worker.start() }
        }
        .defaultSize(width: 1360, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Voice") {
                Button("Generate") { model.generate() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isGenerating)
                Button("Stop Generating") { model.stopGenerating() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.isGenerating)
                Divider()
                Button("Open Text File…") { model.openTextFile() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Writing to the helper after it quits must not kill the app.
        signal(SIGPIPE, SIG_IGN)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
