import SwiftUI

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
