import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = Snapshot.requestedDirectory { Task { @MainActor in Snapshot.run(into: dir) }; return }
        let model = SessionViewModel.shared
        HotKeyManager.shared.onAction = { action in
            Task { @MainActor in
                switch action {
                case .hotReload: await model.hotReload()
                case .hotRestart: await model.hotRestart()
                }
            }
        }
        if model.store.globalHotkeysEnabled { HotKeyManager.shared.register() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = SessionViewModel.shared
        guard model.isRunning else { return .terminateNow }
        Task { @MainActor in
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
