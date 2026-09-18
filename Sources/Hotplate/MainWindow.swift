import SwiftUI
import HotplateCore

struct MainWindow: View {
    @Environment(SessionViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            topBar
            controlCard
                .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 12)
            LogView()
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                .padding(.horizontal, 14)
        }
        .background(windowBackdrop)
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: Top bar (replaces the system toolbar; the empty area still drags the window)

    private var topBar: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Spacer()
            editorSplitButton
            Button { model.followLogs.toggle() } label: {
                Image(systemName: "arrow.down.to.line")
                    .foregroundStyle(model.followLogs ? Theme.accentBright : .secondary)
            }
            .buttonStyle(QuietCapsuleStyle(iconOnly: true))
            .help(model.followLogs ? "Following newest log lines. Click to stop.  ⌘⇧F" : "Follow newest log lines.  ⌘⇧F")
            Button { model.clearLogs() } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(QuietCapsuleStyle(iconOnly: true))
            .help("Clear logs  ⌘K")
        }
        .padding(.leading, 80)   // keep clear of the traffic lights
        .padding(.trailing, 14)
        .frame(height: 44)
    }

    private var chevronShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 14, topTrailingRadius: 14)
    }

    /// Two capsules that read as one split button: the name opens the editor, the arrow picks one.
    private var editorSplitButton: some View {
        @Bindable var model = model
        return HStack(spacing: 1) {
            Button { model.openInEditor() } label: {
                Label(model.editorButtonTitle, systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(QuietCapsuleStyle(trailingFlat: true))
            .disabled(!model.canOpenInEditor)
            .help("Open project in \(model.editorButtonTitle)  ⌘E")
            Menu {
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
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24, height: 27)
            .background(chevronShape.fill(.primary.opacity(0.10)))
            .overlay(chevronShape.strokeBorder(.primary.opacity(0.18)))
            .contentShape(chevronShape)
            .help("Choose the editor")
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
                        .help("Stop the app  ⌘.")
                } else {
                    Button { Task { await model.run() } } label: { Label("Run", systemImage: "play.fill") }
                        .buttonStyle(ProminentCapsuleStyle())
                        .disabled(!model.canRun)
                        .opacity(model.canRun ? 1 : 0.45)
                        .help(model.canRun ? "Run on the selected device  ⌘⏎" : "Pick a project and a device to run")
                }
                Button { Task { await model.hotReload() } } label: { Label("Hot reload", systemImage: "bolt.fill") }
                    .buttonStyle(QuietCapsuleStyle()).disabled(!model.canReload)
                    .help("Hot reload  ⌘R  (⌃⌥R from any app)")
                Button { Task { await model.hotRestart() } } label: { Label("Hot restart", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(QuietCapsuleStyle()).disabled(!model.canReload)
                    .help("Hot restart  ⌘⇧R  (⌃⌥⇧R from any app)")
                Spacer()
                Toggle(isOn: $model.autoReload) {
                    Label("Reload on save", systemImage: "wand.and.stars")
                        .font(.system(size: 12))
                        .foregroundStyle(model.autoReload ? .primary : .secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.accent)
                .help("Hot reload whenever a .dart file in lib/ is saved  ⌘⇧A")
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
        .help((model.project?.path ?? "Pick a Flutter project folder") + "  ⌘O opens a folder")
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
            .help("Target device")
            Button { Task { await model.refreshDevices() } } label: {
                if model.isLoadingDevices { ProgressView().controlSize(.mini) }
                else { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)) }
            }
            .buttonStyle(.borderless)
            .disabled(model.isLoadingDevices || model.isRunning)
            .help(model.deviceError ?? "Refresh devices  ⌘⇧D")
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
        .help("Launch configuration from .vscode/launch.json; the args field below follows it")
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
