import SwiftUI
import FlutterRunnerCore

struct MainWindow: View {
    @Environment(SessionViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            controlCard
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
            LogView()
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                .padding(.horizontal, 14)
        }
        .background(windowBackdrop)
        .toolbar {
            ToolbarItem(placement: .automatic) { editorMenu }
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $model.followLogs) { Label("Follow", systemImage: "arrow.down.to.line") }
                    .help("Keep the newest log line in view")
            }
            ToolbarItem(placement: .automatic) {
                Button { model.clearLogs() } label: { Label("Clear", systemImage: "trash") }.help("Clear logs (⌘K)")
            }
        }
    }

    // MARK: Backdrop

    private var windowBackdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }

    // MARK: Control card

    private var controlCard: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                projectPicker
                devicePicker
                if !model.launchConfigs.isEmpty { launchConfigPicker }
                Spacer(minLength: 0)
                StatusPill(state: model.state, text: model.statusText)
            }
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Extra flutter run arguments, e.g. --flavor dev -t lib/main_dev.dart", text: $model.extraArgs)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .disabled(model.isRunning)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.12)))

            HStack(spacing: 8) {
                if model.canStop {
                    Button { Task { await model.stop() } } label: { Label("Stop", systemImage: "stop.fill") }
                        .buttonStyle(ProminentCapsuleStyle(tint: Theme.error))
                } else {
                    Button { Task { await model.run() } } label: { Label("Run", systemImage: "play.fill") }
                        .buttonStyle(ProminentCapsuleStyle())
                        .disabled(!model.canRun)
                        .opacity(model.canRun ? 1 : 0.45)
                }
                Button { Task { await model.hotReload() } } label: { Label("Hot reload", systemImage: "bolt.fill") }
                    .buttonStyle(QuietCapsuleStyle()).disabled(!model.canReload)
                Button { Task { await model.hotRestart() } } label: { Label("Hot restart", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(QuietCapsuleStyle()).disabled(!model.canReload)
                Spacer()
                Toggle(isOn: $model.autoReload) {
                    Label("Reload on save", systemImage: "wand.and.stars")
                        .font(.system(size: 12))
                        .foregroundStyle(model.autoReload ? .primary : .secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.accent)
            }
        }
        .padding(14)
        .cardSurface()
    }

    private var projectPicker: some View {
        Menu {
            ForEach(model.store.recents) { p in
                Button { model.selectProject(path: p.path) } label: {
                    Text(p.name); Text(abbreviate(p.path))
                }
                .disabled(model.isRunning)
            }
            if !model.store.recents.isEmpty { Divider() }
            Button("Open folder…") { model.openProjectPanel() }.disabled(model.isRunning)
            if let p = model.project {
                Divider()
                Button("Remove \(p.name) from recents") { model.removeRecent(path: p.path) }.disabled(model.isRunning)
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.path)]) }
            }
        } label: {
            Label {
                Text(model.project?.name ?? "Choose project").fontWeight(.semibold)
            } icon: {
                Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(model.project?.path ?? "Pick a Flutter project folder")
    }

    private var devicePicker: some View {
        HStack(spacing: 2) {
            Picker(selection: Binding(get: { model.selectedDeviceId ?? "" },
                                      set: { model.selectedDeviceId = $0.isEmpty ? nil : $0 })) {
                if model.devices.isEmpty { Text(model.isLoadingDevices ? "Looking for devices…" : "No devices").tag("") }
                ForEach(model.devices) { d in
                    Label(d.displayName, systemImage: deviceSymbol(d)).tag(d.id)
                }
            } label: { EmptyView() }
            .labelsHidden()
            .disabled(model.isRunning || model.devices.isEmpty)
            .fixedSize()
            Button { Task { await model.refreshDevices() } } label: {
                if model.isLoadingDevices { ProgressView().controlSize(.mini) }
                else { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)) }
            }
            .buttonStyle(.borderless)
            .disabled(model.isLoadingDevices || model.isRunning)
            .help(model.deviceError ?? "Refresh devices (⌘⇧D)")
        }
    }

    private var launchConfigPicker: some View {
        Picker(selection: Binding(get: { model.selectedLaunchConfigName ?? "" },
                                  set: { model.selectLaunchConfig(name: $0.isEmpty ? nil : $0) })) {
            ForEach(model.launchConfigs) { c in Label(c.name, systemImage: "slider.horizontal.3").tag(c.name) }
            Divider()
            Label("Custom arguments", systemImage: "pencil").tag("")
        } label: { EmptyView() }
        .labelsHidden()
        .fixedSize()
        .disabled(model.isRunning)
        .help("Configurations from .vscode/launch.json")
    }

    /// Split button: primary click opens the project in the chosen editor, the arrow picks the editor.
    private var editorMenu: some View {
        @Bindable var model = model
        return Menu {
            Picker("Editor", selection: $model.editorSelection) {
                ForEach(model.installedEditors) { e in Text(e.name).tag(e.appPath) }
                if let other = model.otherEditor { Text(other.name).tag(other.appPath) }
                Text("Custom command").tag("custom")
            }
            .pickerStyle(.inline)
            Divider()
            Button("Other application…") { model.chooseEditorApp() }
            SettingsLink { Text("Edit custom command…") }
            Button("Re-scan editors") { model.refreshInstalledEditors() }
        } label: {
            Label(model.editorButtonTitle, systemImage: "chevron.left.forwardslash.chevron.right")
        } primaryAction: {
            model.openInEditor()
        }
        .labelStyle(.titleAndIcon)
        .disabled(model.project == nil)
        .help("Open project in \(model.editorButtonTitle) (⌘E). Use the arrow to pick another editor.")
    }

    private func deviceSymbol(_ d: FlutterDevice) -> String {
        let p = d.targetPlatform
        if p.hasPrefix("ios") { return d.emulator ? "iphone.gen3" : "iphone" }
        if p.hasPrefix("android") { return "smartphone" }
        if p.hasPrefix("darwin") { return "macbook" }
        if p.hasPrefix("web") { return "globe" }
        return "display"
    }

    private func abbreviate(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
}
