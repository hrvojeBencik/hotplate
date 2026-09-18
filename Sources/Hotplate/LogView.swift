import SwiftUI
import HotplateCore

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
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "hotplate", url.host == "open",
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let location = items.first(where: { $0.name == "loc" })?.value else { return .systemAction }
            let line = items.first(where: { $0.name == "line" })?.value.flatMap(Int.init)
            let column = items.first(where: { $0.name == "col" })?.value.flatMap(Int.init)
            model.openLogLink(location: location, line: line, column: column)
            return .handled
        })
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

    /// The line with Dart source references turned into links that `LogView` routes to the editor.
    private var attributed: AttributedString {
        var text = AttributedString(line.text)
        for link in LogLinkParser.links(in: line.text) {
            guard let range = Range(link.range, in: text) else { continue }
            var comps = URLComponents(); comps.scheme = "hotplate"; comps.host = "open"
            comps.queryItems = [URLQueryItem(name: "loc", value: link.location)]
                + (link.line.map { [URLQueryItem(name: "line", value: String($0))] } ?? [])
                + (link.column.map { [URLQueryItem(name: "col", value: String($0))] } ?? [])
            text[range].link = comps.url
            text[range].underlineStyle = .single
            text[range].foregroundColor = Theme.info
        }
        return text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Theme.timeFormatter.string(from: line.time))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.logMuted.opacity(0.7))
            Text(attributed)
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
