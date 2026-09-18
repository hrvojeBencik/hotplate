import SwiftUI
import FlutterRunnerCore

@main
struct FlutterRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = SessionViewModel.shared

    var body: some Scene {
        Window("FlutterRunner", id: "main") {
            MainWindow().environment(model).frame(minWidth: 720, minHeight: 420)
        }
        .defaultSize(width: 960, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project…") { model.openProjectPanel() }.keyboardShortcut("o")
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
                Toggle("Auto Reload on Save", isOn: Binding(get: { model.autoReload }, set: { model.autoReload = $0 }))
                Button("Refresh Devices") { Task { await model.refreshDevices() } }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Clear Logs") { model.clearLogs() }.keyboardShortcut("k")
            }
        }

        MenuBarExtra {
            MenuBarMenu().environment(model)
        } label: {
            Image(systemName: menuBarSymbol)
        }

        Settings { SettingsView().environment(model) }
    }

    private var menuBarSymbol: String {
        switch model.state {
        case .idle: return "play.circle"
        case .starting, .stopping: return "circle.dotted"
        case .running: return "play.circle.fill"
        case .reloading, .restarting: return "arrow.triangle.2.circlepath.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }
}
