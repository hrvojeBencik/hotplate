import SwiftUI

/// The menu bar popover: a compact remote control for the running session.
struct MenuBarPanel: View {
    @Environment(SessionViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.project?.name ?? "No project")
                        .font(.system(size: 15, weight: .semibold))
                    Text(model.selectedDevice?.displayName ?? "No device")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(state: model.state, text: model.statusText)
            }

            HStack(spacing: 8) {
                if model.canStop {
                    tile("Stop", "stop.fill", tint: Theme.error) { Task { await model.stop() } }
                } else {
                    tile("Run", "play.fill", tint: Theme.accent, enabled: model.canRun) { Task { await model.run() } }
                }
                tile("Reload", "bolt.fill", enabled: model.canReload) { Task { await model.hotReload() } }
                tile("Restart", "arrow.counterclockwise", enabled: model.canReload) { Task { await model.hotRestart() } }
            }

            Toggle(isOn: $model.autoReload) {
                Label("Reload on save", systemImage: "wand.and.stars").font(.system(size: 12))
            }
            .toggleStyle(.switch).controlSize(.small).tint(Theme.accent)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                row("Open in \(model.editorButtonTitle)", "chevron.left.forwardslash.chevron.right", enabled: model.canOpenInEditor) { model.openInEditor() }
                row("Show logs", "text.alignleft") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                SettingsLink { rowLabel("Settings…", "gearshape") }.buttonStyle(RowStyle())
                row("Quit FlutterRunner", "power") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func tile(_ title: String, _ symbol: String, tint: Color? = nil, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .foregroundStyle(tint == nil ? Color.primary : Color.white)
            .background {
                if let tint { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint == Theme.accent ? AnyShapeStyle(Theme.runGradient) : AnyShapeStyle(tint)) }
                else { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.07)) }
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func row(_ title: String, _ symbol: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, symbol) }.buttonStyle(RowStyle()).disabled(!enabled)
    }

    private func rowLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 16).foregroundStyle(.secondary)
            Text(title).font(.system(size: 12))
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private struct RowStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(configuration.isPressed ? 0.12 : 0)))
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}
