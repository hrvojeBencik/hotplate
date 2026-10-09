/// One of the 16 ANSI colors, so the user's terminal theme decides the actual shade.
public struct TermColor: Hashable, Sendable {
    public let index: UInt8
    public init(index: UInt8) { self.index = index }

    public static let black = TermColor(index: 0)
    public static let red = TermColor(index: 1)
    public static let green = TermColor(index: 2)
    public static let yellow = TermColor(index: 3)
    public static let blue = TermColor(index: 4)
    public static let magenta = TermColor(index: 5)
    public static let cyan = TermColor(index: 6)
    public static let white = TermColor(index: 7)
    public static let gray = TermColor(index: 8)
}

public struct Style: Hashable, Sendable {
    public var fg: TermColor?
    public var bg: TermColor?
    public var bold: Bool
    public var dim: Bool
    public var underline: Bool
    public var inverse: Bool

    public init(fg: TermColor? = nil, bg: TermColor? = nil, bold: Bool = false, dim: Bool = false,
                underline: Bool = false, inverse: Bool = false) {
        self.fg = fg; self.bg = bg; self.bold = bold; self.dim = dim; self.underline = underline; self.inverse = inverse
    }

    public static let plain = Style()

    /// SGR sequence that resets, then applies this style.
    public var sgr: String {
        var codes = ["0"]
        if bold { codes.append("1") }
        if dim { codes.append("2") }
        if underline { codes.append("4") }
        if inverse { codes.append("7") }
        if let fg { codes.append(fg.index < 8 ? "3\(fg.index)" : "9\(fg.index - 8)") }
        if let bg { codes.append(bg.index < 8 ? "4\(bg.index)" : "10\(bg.index - 8)") }
        return "\u{1B}[" + codes.joined(separator: ";") + "m"
    }
}
