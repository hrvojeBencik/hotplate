import Foundation
import HotplateCore

public struct VisualRow: Equatable, Sendable {
    public let lineId: Int
    /// This row's part of the sanitized line.
    public let text: String
    /// Character offset of `text` within the sanitized line.
    public let startOffset: Int
    public let isFirst: Bool
}

public struct LogEntry: Sendable {
    public let text: String
    public let kind: LogKind
    public let time: Date
    public let rows: [VisualRow]
}

/// The wrapped, scrollable log: which rows are visible, what is selected, what a search matches.
public struct LogViewport {
    /// Columns before the text: selection marker, `HH:mm:ss`, two spaces.
    public static let gutter = 11

    public private(set) var rows: [VisualRow] = []
    public private(set) var top = 0
    public private(set) var height = 0
    public private(set) var follow = true
    public private(set) var selectedLineId: Int?
    public private(set) var searchQuery: String?
    private var lineIds: [Int] = []
    private var entries: [Int: LogEntry] = [:]
    private var wrapWidth = 0

    public init() {}

    public func entry(_ lineId: Int) -> LogEntry? { entries[lineId] }
    private var maxTop: Int { max(0, rows.count - height) }
    public var visibleRows: ArraySlice<VisualRow> { rows[min(top, rows.count)..<min(rows.count, top + height)] }

    public mutating func update(lines: [LogLine], width: Int, height: Int) {
        let textWidth = max(1, width - Self.gutter)
        if textWidth != wrapWidth { entries = [:]; wrapWidth = textWidth }
        let anchor = follow || !rows.indices.contains(top) ? nil : rows[top]
        var newRows: [VisualRow] = []
        newRows.reserveCapacity(rows.count + 16)
        for line in lines {
            if let e = entries[line.id] { newRows += e.rows; continue }
            let text = LogText.sanitize(line.text)
            let e = LogEntry(text: text, kind: line.kind, time: line.time, rows: Self.wrap(lineId: line.id, text: text, width: textWidth))
            entries[line.id] = e
            newRows += e.rows
        }
        if entries.count > lines.count + 1000 {
            let ids = Set(lines.map(\.id))
            entries = entries.filter { ids.contains($0.key) }
        }
        lineIds = lines.map(\.id)
        rows = newRows
        self.height = max(0, height)
        if let s = selectedLineId, !lineIds.contains(s) { selectedLineId = nil }
        if follow {
            top = maxTop
        } else if let anchor,
                  let i = rows.firstIndex(where: { $0.lineId == anchor.lineId && $0.startOffset == anchor.startOffset })
                    ?? rows.firstIndex(where: { $0.lineId == anchor.lineId }) {
            top = min(i, maxTop)
        } else {
            top = min(top, maxTop)
        }
    }

    // MARK: Scrolling

    public mutating func scroll(by delta: Int) {
        top = min(max(0, top + delta), maxTop)
        follow = top >= maxTop
    }

    public mutating func scrollToTop() { top = 0; follow = maxTop == 0 }
    public mutating func scrollToBottom() { top = maxTop; follow = true }

    public mutating func setFollow(_ on: Bool) {
        if on { selectedLineId = nil; scrollToBottom() } else { follow = false }
    }

    // MARK: Selection

    public mutating func select(lineId: Int?) {
        selectedLineId = lineId
        guard let lineId, let first = rows.firstIndex(where: { $0.lineId == lineId }) else { return }
        follow = false
        let last = rows.lastIndex(where: { $0.lineId == lineId }) ?? first
        if first < top { top = first }
        else if last >= top + height { top = min(maxTop, max(first, last - height + 1)) }
    }

    public mutating func moveSelection(by delta: Int) {
        guard let current = selectedLineId, let i = lineIds.firstIndex(of: current) else { return }
        select(lineId: lineIds[min(max(0, i + delta), lineIds.count - 1)])
    }

    // MARK: Links

    public func links(onLine id: Int) -> [LogLink] { entries[id].map { LogLinkParser.links(in: $0.text) } ?? [] }

    /// The newest line with an error and a link, else the newest line with a link.
    public func lastLinkLine() -> Int? {
        let withLinks = lineIds.filter { !links(onLine: $0).isEmpty }
        return withLinks.last(where: { entries[$0]?.kind == .error }) ?? withLinks.last
    }

    /// The next line with a link after `from` (or from the start/end when nil).
    public func linkLine(from lineId: Int?, forward: Bool) -> Int? {
        let ids = forward ? lineIds : Array(lineIds.reversed())
        let start = lineId.flatMap { id in ids.firstIndex(of: id).map { $0 + 1 } } ?? 0
        guard start < ids.count else { return nil }
        return ids[start...].first { !links(onLine: $0).isEmpty }
    }

    public static func offsets(of link: LogLink, in text: String) -> Range<Int> {
        text.distance(from: text.startIndex, to: link.range.lowerBound)..<text.distance(from: text.startIndex, to: link.range.upperBound)
    }

    /// The line under a log-area position (row 0 = first visible row) and the link under the column, if any.
    public func hit(row: Int, column: Int) -> (lineId: Int, link: LogLink?)? {
        let index = top + row
        guard row >= 0, row < height, rows.indices.contains(index) else { return nil }
        let r = rows[index]
        guard column >= Self.gutter, let text = entries[r.lineId]?.text else { return (r.lineId, nil) }
        var col = Self.gutter, offset = r.startOffset
        var hitOffset: Int?
        for c in r.text {
            let w = CharWidth.of(c)
            if column < col + w { hitOffset = offset; break }
            col += w; offset += 1
        }
        guard let hitOffset else { return (r.lineId, nil) }
        let link = LogLinkParser.links(in: text).first { Self.offsets(of: $0, in: text).contains(hitOffset) }
        return (r.lineId, link)
    }

    // MARK: Search

    public mutating func setSearch(_ query: String?) {
        searchQuery = (query ?? "").isEmpty ? nil : query
    }

    /// The next line containing the search text after `from`, wrapping around.
    public func searchMatch(from lineId: Int?, forward: Bool) -> Int? {
        guard let q = searchQuery else { return nil }
        let ids = forward ? lineIds : Array(lineIds.reversed())
        let matches = { (id: Int) in entries[id]?.text.range(of: q, options: .caseInsensitive) != nil }
        let start = min(ids.count, lineId.flatMap { id in ids.firstIndex(of: id).map { $0 + 1 } } ?? 0)
        return ids[start...].first(where: matches) ?? ids[..<start].first(where: matches)
    }

    // MARK: Wrapping

    static func wrap(lineId: Int, text: String, width: Int) -> [VisualRow] {
        var rows: [VisualRow] = []
        var current = "", used = 0, start = 0, offset = 0
        for c in text {
            let w = CharWidth.of(c)
            if used + w > width, !current.isEmpty {
                rows.append(VisualRow(lineId: lineId, text: current, startOffset: start, isFirst: rows.isEmpty))
                current = ""; used = 0; start = offset
            }
            current.append(c); used += w; offset += 1
        }
        rows.append(VisualRow(lineId: lineId, text: current, startOffset: start, isFirst: rows.isEmpty))
        return rows
    }
}
