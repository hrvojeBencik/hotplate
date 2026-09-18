import SwiftUI
import FlutterRunnerCore

struct MainWindow: View {
    @Environment(SessionViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    projectPicker
                    devicePicker
                    TextField("Extra args, e.g. --flavor dev -t lib/main_dev.dart", text: $model.extraArgs)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.isRunning)
                        .frame(minWidth: 220)
                }
                HStack(spacing: 10) {
                    if model.canStop {
                        Button { Task { await model.stop() } } label: { Label("Stop", systemImage: "stop.fill") }
                    } else {
                        Button { Task { await model.run() } } label: { Label("Run", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent).disabled(!model.canRun)
                    }
                    Button { Task { await model.hotReload() } } label: { Label("Hot Reload", systemImage: "bolt.fill") }
                        .disabled(!model.canReload)
                    Button { Task { await model.hotRestart() } } label: { Label("Hot Restart", systemImage: "arrow.counterclockwise") }
                        .disabled(!model.canReload)
                    Toggle("Auto reload", isOn: $model.autoReload).toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    statusIndicator
                }
            }
            .padding(12)
            Divider()
            LogView()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $model.followLogs) { Label("Follow", systemImage: "arrow.down.to.line") }
                    .help("Auto-scroll to newest log line")
            }
            ToolbarItem(placement: .automatic) {
                Button { model.clearLogs() } label: { Label("Clear", systemImage: "trash") }.help("Clear logs (⌘K)")
            }
        }
    }

    private var projectPicker: some View {
        Menu {
            ForEach(model.store.recents) { p in
                Button(p.name + "  —  " + abbreviate(p.path)) { model.selectProject(path: p.path) }
            }
            if !model.store.recents.isEmpty { Divider() }
            Button("Open Folder…") { model.openProjectPanel() }
            if let p = model.project {
                Divider()
                Button("Remove \(p.name) from Recents") { model.removeRecent(path: p.path) }
            }
        } label: {
            Label(model.project?.name ?? "Choose project", systemImage: "folder")
        }
        .disabled(model.isRunning)
        .frame(maxWidth: 260)
    }

    private var devicePicker: some View {
        HStack(spacing: 4) {
            Picker("Device", selection: Binding(get: { model.selectedDeviceId ?? "" },
                                                set: { model.selectedDeviceId = $0.isEmpty ? nil : $0 })) {
                if model.devices.isEmpty { Text(model.isLoadingDevices ? "Loading…" : "No devices").tag("") }
                ForEach(model.devices) { d in Text(d.displayName).tag(d.id) }
            }
            .labelsHidden()
            .disabled(model.isRunning || model.devices.isEmpty)
            .frame(maxWidth: 240)
            Button { Task { await model.refreshDevices() } } label: {
                if model.isLoadingDevices { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
            }
            .disabled(model.isLoadingDevices || model.isRunning)
            .help(model.deviceError ?? "Refresh devices (⌘⇧D)")
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(model.statusText).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .idle: return .gray
        case .starting, .stopping: return .blue
        case .running: return .green
        case .reloading, .restarting: return .yellow
        case .failed: return .red
        }
    }

    private func abbreviate(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
}
