/// A one-line editor shown in the footer, for run arguments and search.
public struct TextInput: Equatable {
    public enum Outcome: Equatable { case editing, submit, cancel }

    public private(set) var text: String
    /// Character index of the cursor.
    public private(set) var cursor: Int

    public init(text: String) { self.text = text; cursor = text.count }

    public mutating func insert(_ s: String) {
        let chars = Array(text)
        let prefix = String(chars[0..<min(cursor, chars.count)]) + s
        text = prefix + String(chars[min(cursor, chars.count)...])
        cursor = prefix.count
    }

    public mutating func handle(_ key: Key) -> Outcome {
        var chars = Array(text)
        switch key {
        case .enter: return .submit
        case .escape: return .cancel
        case .char(let c): insert(String(c)); return .editing
        case .backspace: if cursor > 0 { chars.remove(at: cursor - 1); cursor -= 1 }
        case .delete: if cursor < chars.count { chars.remove(at: cursor) }
        case .left: cursor = max(0, cursor - 1)
        case .right: cursor = min(chars.count, cursor + 1)
        case .home, .ctrl("a"): cursor = 0
        case .end, .ctrl("e"): cursor = chars.count
        case .ctrl("u"): chars.removeSubrange(0..<cursor); cursor = 0
        case .ctrl("w"):
            var i = cursor
            while i > 0, chars[i - 1] == " " { i -= 1 }
            while i > 0, chars[i - 1] != " " { i -= 1 }
            chars.removeSubrange(i..<cursor); cursor = i
        default: return .editing
        }
        text = String(chars)
        cursor = min(cursor, text.count)
        return .editing
    }

    public func draw(into buf: inout ScreenBuffer, y: Int, prompt: String) {
        buf.fill(y: y, style: .plain)
        let x0 = 1 + buf.put(prompt, x: 1, y: y, style: Style(fg: .yellow, bold: true))
        let room = max(1, buf.width - x0 - 1)
        let chars = Array(text)
        let start = max(0, cursor - room + 1)
        var x = x0
        for i in start..<chars.count {
            if x >= buf.width - 1 { break }
            x += buf.put(String(chars[i]), x: x, y: y, style: i == cursor ? Style(inverse: true) : .plain)
        }
        if cursor == chars.count { buf.put(" ", x: x, y: y, style: Style(inverse: true)) }
    }
}
