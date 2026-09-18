import SwiftUI

struct LogView: View {
    @Environment(SessionViewModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.logs) { line in
                        Text(line.text)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(color(for: line.kind))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: model.logs.count) { _, _ in
                if model.followLogs, let last = model.logs.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(for kind: LogKind) -> Color {
        switch kind {
        case .normal: return .primary
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        case .success: return .green
        }
    }
}
