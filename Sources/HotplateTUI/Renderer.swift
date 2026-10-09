/// Emits only what changed since the previous frame: cursor moves, style changes and characters.
public struct Renderer {
    private var previous: ScreenBuffer?

    public init() {}

    /// The next frame is drawn from scratch (after resize or Ctrl+L).
    public mutating func invalidate() { previous = nil }

    public mutating func render(_ frame: ScreenBuffer) -> String {
        var out = ""
        let old = previous.flatMap { $0.width == frame.width && $0.height == frame.height ? $0 : nil }
        if old == nil { out += "\u{1B}[0m\u{1B}[2J" }
        var style: Style?
        var cursor: (x: Int, y: Int)?
        for y in 0..<frame.height {
            var x = 0
            while x < frame.width {
                let cell = frame[x, y]
                if cell.width == 0 { x += 1; continue }
                if let old, old[x, y] == cell, cell.width == 1 || old[x + 1, y] == frame[x + 1, y] {
                    x += cell.width
                    continue
                }
                if cursor.map({ $0.x != x || $0.y != y }) ?? true { out += "\u{1B}[\(y + 1);\(x + 1)H" }
                if style != cell.style { out += cell.style.sgr; style = cell.style }
                out.append(cell.char)
                x += cell.width
                cursor = (x, y)
            }
        }
        if style != nil { out += "\u{1B}[0m" }
        previous = frame
        return out
    }
}
