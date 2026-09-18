import SwiftUI

struct LogView: View {
    @Environment(SessionViewModel.self) private var model

    var body: some View {
        ZStack {
            Theme.logCanvas
            if model.logs.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.logs) { line in LogRow(line: line).id(line.id) }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: model.logs.count) { _, _ in
                        if model.followLogs, let last = model.logs.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.logMuted)
            Text(model.project == nil ? "Choose a project to get started." : "Press Run to launch \(model.project!.name).")
                .font(.system(size: 13))
                .foregroundStyle(Theme.logMuted)
            Text("Saving a .dart file in lib/ reloads the app while it runs.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.logMuted.opacity(0.7))
        }
    }
}

private struct LogRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Theme.timeFormatter.string(from: line.time))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.logMuted.opacity(0.7))
            Text(line.text)
                .font(.system(size: 12, weight: line.kind == .success ? .medium : .regular, design: .monospaced))
                .foregroundStyle(Theme.color(for: line.kind))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
        .background {
            if line.kind == .error {
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.error).frame(width: 2)
                    Theme.error.opacity(0.08)
                }
            }
        }
    }
}
