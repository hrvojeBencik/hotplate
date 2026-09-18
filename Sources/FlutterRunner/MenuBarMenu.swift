import SwiftUI

struct MenuBarMenu: View {
    @Environment(SessionViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        Text(model.project?.name ?? "No project")
        Text(model.selectedDevice?.displayName ?? "No device")
        Text(model.statusText)
        Divider()
        if model.canStop {
            Button("Stop") { Task { await model.stop() } }
        } else {
            Button("Run") { Task { await model.run() } }.disabled(!model.canRun)
        }
        Button("Hot Reload") { Task { await model.hotReload() } }.disabled(!model.canReload)
        Button("Hot Restart") { Task { await model.hotRestart() } }.disabled(!model.canReload)
        Toggle("Auto Reload on Save", isOn: $model.autoReload)
        Divider()
        Button("Open in Editor") { model.openInEditor() }.disabled(!model.canOpenInEditor)
        Button("Show Logs") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit FlutterRunner") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
