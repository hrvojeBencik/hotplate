import SwiftUI
import FlutterRunnerCore

struct SettingsView: View {
    @Environment(SessionViewModel.self) private var model

    var body: some View {
        @Bindable var store = model.store
        Form {
            Section("Flutter") {
                TextField("Flutter path (leave empty to auto-detect)", text: $store.manualFlutterPath)
                    .onSubmit { model.relocateFlutter() }
                HStack {
                    Text("Detected: \(model.flutterPath ?? "not found")").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Re-detect") { model.relocateFlutter() }
                }
            }
            Section("Editor") {
                Picker("Open project with", selection: Binding(
                    get: { store.editorUseCustomCommand ? "custom" : store.editorAppPath },
                    set: { value in
                        if value == "custom" { store.editorUseCustomCommand = true }
                        else if value == "choose" { model.chooseEditorApp() }
                        else { store.editorUseCustomCommand = false; store.editorAppPath = value }
                    })) {
                    Text("Automatic (\(model.installedEditors.first?.name ?? "none found"))").tag("")
                    ForEach(model.installedEditors) { e in Text(e.name).tag(e.appPath) }
                    if !store.editorAppPath.isEmpty, !model.installedEditors.contains(where: { $0.appPath == store.editorAppPath }) {
                        Text(EditorLauncher.name(ofApp: store.editorAppPath)).tag(store.editorAppPath)
                    }
                    Divider()
                    Text("Other application…").tag("choose")
                    Text("Custom command").tag("custom")
                }
                if store.editorUseCustomCommand {
                    TextField("Command, e.g. zed {path}  or  open -a kitty --args nvim {path}", text: $store.editorCustomCommand)
                    Text("Runs in your login shell; {path} is replaced with the project folder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Will open with: \(store.editorUseCustomCommand ? store.editorCustomCommand : (model.effectiveEditor?.name ?? "nothing"))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Re-scan") { model.refreshInstalledEditors() }
                }
            }
            Section("Auto reload") {
                Stepper("Debounce: \(store.debounceMs) ms", value: $store.debounceMs, in: 100...3000, step: 100)
                Text("Changes to .dart files under lib/ within this window are merged into one hot reload.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}
