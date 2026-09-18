import SwiftUI
import HotplateCore

@main
struct HotplateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = SessionViewModel.shared

    var body: some Scene {
        Window("Hotplate", id: "main") {
            MainWindow().environment(model).frame(minWidth: 720, minHeight: 420)
        }
        .defaultSize(width: 960, height: 600)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project…") { model.openProjectPanel() }.keyboardShortcut("o")
                Button("Open in Editor") { model.openInEditor() }.keyboardShortcut("e").disabled(!model.canOpenInEditor)
            }
            CommandMenu("Flutter") {
                Button("Run") { Task { await model.run() } }
                    .keyboardShortcut(.return, modifiers: .command).disabled(!model.canRun)
                Button("Stop") { Task { await model.stop() } }
                    .keyboardShortcut(".", modifiers: .command).disabled(!model.canStop)
                Divider()
                Button("Hot Reload") { Task { await model.hotReload() } }
                    .keyboardShortcut("r").disabled(!model.canReload)
                Button("Hot Restart") { Task { await model.hotRestart() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!model.canReload)
                Divider()
                Toggle("Reload on Save", isOn: Binding(get: { model.autoReload }, set: { model.autoReload = $0 }))
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Refresh Devices") { Task { await model.refreshDevices() } }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Toggle("Follow Logs", isOn: Binding(get: { model.followLogs }, set: { model.followLogs = $0 }))
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Clear Logs") { model.clearLogs() }.keyboardShortcut("k")
            }
        }

        MenuBarExtra {
            MenuBarPanel().environment(model)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView().environment(model) }
    }

    private var menuBarSymbol: String {
        switch model.state {
        case .idle: return "bolt.circle"
        case .starting, .stopping: return "ellipsis.circle"
        case .running: return "bolt.circle.fill"
        case .reloading, .restarting: return "arrow.triangle.2.circlepath.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}
