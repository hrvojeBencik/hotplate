public struct Cell: Equatable, Sendable {
    public var char: Character
    /// 1 or 2 for a visible character; 0 for the right half of a wide character.
    public var width: Int
    public var style: Style

    public static let blank = Cell(char: " ", width: 1, style: .plain)
}

/// A grid of cells that widgets draw into; `Renderer` turns it into terminal output.
public struct ScreenBuffer: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var cells: [Cell]

    public init(width: Int, height: Int) {
        self.width = max(0, width); self.height = max(0, height)
        cells = Array(repeating: .blank, count: self.width * self.height)
    }

    public subscript(x: Int, y: Int) -> Cell { cells[y * width + x] }

    /// Writes `text` at (x, y), clipped to `maxWidth` columns and the right edge. Returns the columns used.
    @discardableResult
    public mutating func put(_ text: String, x: Int, y: Int, style: Style = .plain, maxWidth: Int? = nil) -> Int {
        guard y >= 0, y < height, x >= 0, x < width else { return 0 }
        let limit = min(width, x + (maxWidth ?? width))
        var col = x
        for c in text {
            let w = CharWidth.of(c)
            if w == 0 { continue }
            if col + w > limit { break }
            clearWideHalves(x: col, y: y, width: w)
            cells[y * width + col] = Cell(char: c, width: w, style: style)
            if w == 2 { cells[y * width + col + 1] = Cell(char: " ", width: 0, style: style) }
            col += w
        }
        return col - x
    }

    public mutating func fill(x: Int = 0, y: Int, width w: Int? = nil, style: Style) {
        guard y >= 0, y < height else { return }
        let start = max(0, x), end = min(width, x + (w ?? width))
        guard start < end else { return }
        clearWideHalves(x: start, y: y, width: end - start)
        for col in start..<end { cells[y * width + col] = Cell(char: " ", width: 1, style: style) }
    }

    /// Before columns x..<x+w are overwritten: blanks the half of a wide character that would be left orphaned
    /// (its left half when the span starts on a right half, its right half when the span ends on a left half).
    private mutating func clearWideHalves(x: Int, y: Int, width w: Int) {
        let row = y * width
        if x > 0, cells[row + x].width == 0 {
            cells[row + x - 1] = Cell(char: " ", width: 1, style: cells[row + x - 1].style)
        }
        let last = x + w - 1
        if last + 1 < width, cells[row + last].width == 2 {
            cells[row + last + 1] = Cell(char: " ", width: 1, style: cells[row + last + 1].style)
        }
    }

    /// Plain text of a row, for tests and debugging.
    public func text(row y: Int) -> String {
        (0..<width).compactMap { x -> String? in
            let c = self[x, y]
            return c.width == 0 ? nil : String(c.char)
        }.joined()
    }
}
