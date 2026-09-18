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
                @Bindable var model = model
                Picker("Open project with", selection: $model.editorSelection) {
                    if model.installedEditors.isEmpty, model.otherEditor == nil { Text("No editor found").tag("") }
                    ForEach(model.installedEditors) { e in Text(e.name).tag(e.appPath) }
                    if let other = model.otherEditor { Text(other.name).tag(other.appPath) }
                    Text("Custom command").tag("custom")
                }
                Button("Other application…") { model.chooseEditorApp() }
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
