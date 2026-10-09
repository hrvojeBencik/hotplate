public struct TerminalSize: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

public enum PickerKind: Equatable, Sendable { case device, config, editor, project }

public struct PickerItem: Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let isCurrent: Bool

    public init(id: String, title: String, detail: String, isCurrent: Bool) {
        self.id = id; self.title = title; self.detail = detail; self.isCurrent = isCurrent
    }
}

/// A centered list with type-to-filter, used for devices, configurations, editors and projects.
public struct Picker: Equatable {
    public let kind: PickerKind
    public private(set) var items: [PickerItem]
    public private(set) var filter: String
    public private(set) var selectedIndex = 0

    public init(kind: PickerKind, items: [PickerItem], filter: String = "") {
        self.kind = kind; self.items = items; self.filter = filter
        selectedIndex = filtered.firstIndex(where: \.isCurrent) ?? 0
    }

    public var filtered: [PickerItem] {
        guard !filter.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(filter) || $0.id.localizedCaseInsensitiveContains(filter)
                || $0.detail.localizedCaseInsensitiveContains(filter)
        }
    }

    public var selected: PickerItem? {
        let f = filtered
        return f.indices.contains(selectedIndex) ? f[selectedIndex] : nil
    }

    public var title: String {
        switch kind {
        case .device: return "Devices"
        case .config: return "Launch configuration"
        case .editor: return "Editor"
        case .project: return "Recent projects"
        }
    }

    public var emptyMessage: String {
        switch kind {
        case .device: return "No devices. Start one, then press Ctrl+R."
        case .config: return "No configurations."
        case .editor: return "No editors found."
        case .project: return "No recent projects."
        }
    }

    public mutating func type(_ c: Character) { filter.append(c); selectedIndex = 0 }

    public mutating func backspace() {
        guard !filter.isEmpty else { return }
        filter.removeLast(); selectedIndex = 0
    }

    public mutating func move(by delta: Int) {
        let n = filtered.count
        guard n > 0 else { return }
        selectedIndex = min(max(0, selectedIndex + delta), n - 1)
    }

    public mutating func select(index: Int) {
        if filtered.indices.contains(index) { selectedIndex = index }
    }

    /// Replaces the items (e.g. after a device refresh) and keeps the same item selected when it still exists.
    public mutating func setItems(_ newItems: [PickerItem]) {
        guard newItems != items else { return }
        let keep = selected?.id
        items = newItems
        let f = filtered
        selectedIndex = keep.flatMap { id in f.firstIndex { $0.id == id } } ?? min(selectedIndex, max(0, f.count - 1))
    }

    // MARK: Geometry

    struct Box {
        let x: Int, y: Int, width: Int, height: Int
        let listTop: Int, visibleCount: Int, firstIndex: Int
    }

    func box(in size: TerminalSize) -> Box {
        let f = filtered
        let longest = f.map { CharWidth.of($0.title) + CharWidth.of($0.detail) + 8 }.max() ?? 0
        let width = max(10, min(size.width - 4, max(44, longest, CharWidth.of(emptyMessage) + 4)))
        let visible = max(1, min(max(1, size.height - 8), f.count))
        let height = visible + 3
        let x = max(0, (size.width - width) / 2), y = max(1, (size.height - height) / 2)
        let first = max(0, min(selectedIndex - visible + 1, f.count - visible))
        return Box(x: x, y: y, width: width, height: height, listTop: y + 2, visibleCount: visible, firstIndex: first)
    }

    public func contains(x: Int, y: Int, in size: TerminalSize) -> Bool {
        let b = box(in: size)
        return x >= b.x && x < b.x + b.width && y >= b.y && y < b.y + b.height
    }

    public func itemIndex(atX x: Int, y: Int, in size: TerminalSize) -> Int? {
        let b = box(in: size)
        let row = y - b.listTop
        guard contains(x: x, y: y, in: size), row >= 0, row < b.visibleCount else { return nil }
        let index = b.firstIndex + row
        return filtered.indices.contains(index) ? index : nil
    }

    public func draw(into buf: inout ScreenBuffer, busy: Bool) {
        let b = box(in: TerminalSize(width: buf.width, height: buf.height))
        let border = Style(fg: .cyan)
        for row in 0..<b.height { buf.fill(x: b.x, y: b.y + row, width: b.width, style: .plain) }
        let rule = String(repeating: "─", count: max(0, b.width - 2))
        buf.put("┌" + rule + "┐", x: b.x, y: b.y, style: border)
        buf.put("└" + rule + "┘", x: b.x, y: b.y + b.height - 1, style: border)
        for row in 1..<(b.height - 1) {
            buf.put("│", x: b.x, y: b.y + row, style: border)
            buf.put("│", x: b.x + b.width - 1, y: b.y + row, style: border)
        }
        buf.put(" \(title)\(busy ? " · Refreshing…" : "") ", x: b.x + 2, y: b.y, style: Style(bold: true), maxWidth: b.width - 4)
        buf.put("› " + filter + "▏", x: b.x + 2, y: b.y + 1, style: Style(fg: .yellow), maxWidth: b.width - 4)
        let f = filtered
        guard !f.isEmpty else {
            buf.put(emptyMessage, x: b.x + 2, y: b.listTop, style: Style(dim: true), maxWidth: b.width - 4)
            return
        }
        for i in 0..<b.visibleCount {
            let index = b.firstIndex + i
            guard f.indices.contains(index) else { break }
            let item = f[index], y = b.listTop + i, isSelected = index == selectedIndex
            let style = Style(inverse: isSelected)
            if isSelected { buf.fill(x: b.x + 1, y: y, width: b.width - 2, style: style) }
            buf.put(item.isCurrent ? "●" : " ", x: b.x + 2, y: y, style: Style(fg: .green, inverse: isSelected))
            let used = buf.put(item.title, x: b.x + 4, y: y, style: style, maxWidth: b.width - 6)
            let room = b.width - 6 - used - 2
            if room > 3, !item.detail.isEmpty {
                let d = CharWidth.truncate(item.detail, to: room)
                buf.put(d, x: b.x + b.width - 2 - CharWidth.of(d), y: y, style: Style(dim: true, inverse: isSelected))
            }
        }
    }
}
