import Foundation
import HotplateCore

enum Layout {
    /// First screen row of the log area (row 0 is the status bar, row 1 a rule).
    static let logTop = 2
    static let minWidth = 60
    static let minHeight = 12
}

struct StatusInfo {
    var project: String?
    var state: SessionState
    var statusText: String
    var flutterMissing: Bool
    var device: String?
    var config: String?
    var autoReload: Bool
}

enum StatusBar {
    static func draw(_ info: StatusInfo, into buf: inout ScreenBuffer) {
        let width = buf.width

        // Build right part (status + auto-reload)
        let statusText = info.flutterMissing ? "● flutter not found" : "● \(info.statusText)"
        var rightParts: [String] = [statusText]
        if info.autoReload {
            rightParts.append("↻ auto")
        }
        let rightText = rightParts.joined(separator: "  ")
        let rightWidth = CharWidth.of(rightText)

        // Draw right part right-aligned
        let rightX = max(1, width - rightWidth - 1)
        if rightX > 1 {
            var x = rightX
            x += buf.put(statusText, x: x, y: 0, style: info.flutterMissing ?
                Style(fg: .red, bold: true) : Style(fg: color(for: info.state), bold: true))
            if info.autoReload {
                x += buf.put("  ", x: x, y: 0)
                buf.put("↻ auto", x: x, y: 0, style: Style(fg: .cyan))
            }
        }

        // Build and draw left part, truncating as needed
        let availableWidth = rightX - 3
        var device = info.device ?? "no device"
        var config = info.config ?? "custom"
        var project = info.project ?? "no project"

        let minColumnWidth = 6
        while CharWidth.of("Hotplate · \(project)   \(device)   cfg: \(config)") > availableWidth &&
              (CharWidth.of(device) > minColumnWidth ||
               CharWidth.of(config) > minColumnWidth ||
               CharWidth.of(project) > minColumnWidth) {
            if CharWidth.of(device) > minColumnWidth {
                device = CharWidth.truncate(device, to: CharWidth.of(device) - 1)
            } else if CharWidth.of(config) > minColumnWidth {
                config = CharWidth.truncate(config, to: CharWidth.of(config) - 1)
            } else if CharWidth.of(project) > minColumnWidth {
                project = CharWidth.truncate(project, to: CharWidth.of(project) - 1)
            } else {
                break
            }
        }

        var x = 1
        x += buf.put("Hotplate", x: x, y: 0, style: Style(bold: true))
        x += buf.put(" · \(project)", x: x, y: 0)
        x += 3
        x += buf.put(device, x: x, y: 0)
        x += 3
        buf.put("cfg: \(config)", x: x, y: 0, style: Style(dim: true))
    }

    static func color(for state: SessionState) -> TermColor {
        switch state {
        case .idle: return .gray
        case .starting, .stopping: return .cyan
        case .running: return .green
        case .reloading, .restarting: return .yellow
        case .failed: return .red
        }
    }
}

enum FooterBar {
    static func draw(_ items: [FooterItem], into buf: inout ScreenBuffer, y: Int) {
        var x = 1
        for item in items {
            x += buf.put(item.key, x: x, y: y, style: Style(bold: true))
            x += buf.put(" " + item.label, x: x, y: y, style: Style(dim: true))
            x += 2
        }
    }
}

enum HelpOverlay {
    static var lines: [String] {
        KeyBindings.normal.map { $0.keyLabel.padding(toLength: 6, withPad: " ", startingAt: 0) + $0.help }
            + [
                "Click Select a line; click a file link to open it",
                "Wheel Scroll the log",
                "Shift+drag selects text (Option+drag in iTerm2)",
            ]
    }

    static func maxScroll(for size: TerminalSize) -> Int {
        let w = size.width - 4
        let h = size.height - 2
        guard w > 10, h > 4 else { return 0 }
        let columnWidth = 48
        let perColumn = h - 4
        guard perColumn > 0 else { return 0 }
        let fit = columnWidth > 0 ? (w - 4) / columnWidth : 1
        let columns = max(1, fit)
        let needsScrolling = lines.count > columns * perColumn
        let activePerColumn = needsScrolling ? (perColumn - 1) : perColumn
        let maxCapacity = columns * activePerColumn
        return max(0, lines.count - maxCapacity)
    }

    static func draw(into buf: inout ScreenBuffer, scroll: Int) {
        let x0 = 2, y0 = 1, w = buf.width - 4, h = buf.height - 2
        guard w > 10, h > 4 else { return }
        for row in 0..<h { buf.fill(x: x0, y: y0 + row, width: w, style: .plain) }
        let border = Style(fg: .cyan)
        let rule = String(repeating: "─", count: w - 2)
        buf.put("┌" + rule + "┐", x: x0, y: y0, style: border)
        buf.put("└" + rule + "┘", x: x0, y: y0 + h - 1, style: border)
        for row in 1..<(h - 1) {
            buf.put("│", x: x0, y: y0 + row, style: border)
            buf.put("│", x: x0 + w - 1, y: y0 + row, style: border)
        }
        buf.put(" Keyboard shortcuts ", x: x0 + 2, y: y0, style: Style(bold: true))

        let columnWidth = 48
        let perColumn = h - 4
        let columns = max(1, (w - 4) / columnWidth)

        // If content doesn't fit in multi-column, use single-column scrolling
        let needsScrolling = lines.count > columns * perColumn
        let activeColumns = needsScrolling ? 1 : columns
        let activePerColumn = needsScrolling ? (perColumn - 1) : perColumn
        let maxScroll = maxScroll(for: TerminalSize(width: buf.width, height: buf.height))
        let clampedScroll = min(max(0, scroll), maxScroll)

        if needsScrolling {
            // Single column scrolling
            for (i, line) in lines.enumerated() {
                let displayIndex = i - clampedScroll
                guard displayIndex >= 0, displayIndex < activePerColumn else { continue }
                buf.put(line, x: x0 + 2, y: y0 + 2 + displayIndex, maxWidth: columnWidth - 2)
            }
        } else {
            // Multi-column layout
            for (i, line) in lines.enumerated() {
                let column = i / activePerColumn
                guard column < activeColumns else { break }
                buf.put(line, x: x0 + 2 + column * columnWidth, y: y0 + 2 + i % activePerColumn, maxWidth: columnWidth - 2)
            }
        }

        // Draw hint at bottom
        let hintText = maxScroll > 0 ? " ↑↓ scroll · any other key closes " : " any key closes "
        let hintX = (x0 + w) - CharWidth.of(hintText) - 1
        buf.put(hintText, x: max(x0 + 2, hintX), y: y0 + h - 1, style: Style(dim: true))
    }
}

enum LogPane {
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    static func draw(_ v: LogViewport, into buf: inout ScreenBuffer, top: Int) {
        for (i, row) in v.visibleRows.enumerated() {
            let y = top + i
            guard let entry = v.entry(row.lineId) else { continue }
            let selected = row.lineId == v.selectedLineId
            var base = style(for: entry.kind)
            base.inverse = selected
            if selected { buf.fill(y: y, style: Style(inverse: true)) }
            if row.isFirst {
                if selected { buf.put("▶", x: 0, y: y, style: Style(fg: .cyan, inverse: true)) }
                buf.put(timeFormatter.string(from: entry.time), x: 1, y: y, style: Style(dim: true, inverse: selected))
            }
            let links = LogLinkParser.links(in: entry.text).map { LogViewport.offsets(of: $0, in: entry.text) }
            let matches = matchOffsets(in: entry.text, query: v.searchQuery)
            var x = LogViewport.gutter, offset = row.startOffset
            for c in row.text {
                var st = base
                if links.contains(where: { $0.contains(offset) }) {
                    st.underline = true
                    if !selected { st.fg = .blue }
                }
                if matches.contains(where: { $0.contains(offset) }) { st = Style(fg: .black, bg: .yellow) }
                x += buf.put(String(c), x: x, y: y, style: st)
                offset += 1
            }
        }
    }

    static func style(for kind: LogKind) -> Style {
        switch kind {
        case .normal: return .plain
        case .error: return Style(fg: .red)
        case .warning: return Style(fg: .yellow)
        case .info: return Style(fg: .gray)
        case .success: return Style(fg: .green, bold: true)
        }
    }

    private static func matchOffsets(in text: String, query: String?) -> [Range<Int>] {
        guard let query, !query.isEmpty else { return [] }
        var out: [Range<Int>] = []
        var searchStart = text.startIndex
        while let r = text.range(of: query, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            out.append(text.distance(from: text.startIndex, to: r.lowerBound)..<text.distance(from: text.startIndex, to: r.upperBound))
            searchStart = r.upperBound
        }
        return out
    }
}
