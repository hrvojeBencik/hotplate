import Foundation

/// Terminal column width of characters: 0 for marks and controls, 2 for East Asian wide and emoji.
public enum CharWidth {
    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
        0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
        0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD,
    ]

    public static func of(_ c: Character) -> Int {
        guard let scalar = c.unicodeScalars.first else { return 0 }
        let v = scalar.value
        if v < 0x20 || (0x7F..<0xA0).contains(v) { return 0 }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format: return 0
        default: break
        }
        if scalar.properties.isEmojiPresentation || c.unicodeScalars.contains(where: { $0.value == 0xFE0F }) { return 2 }
        if wideRanges.contains(where: { $0.contains(v) }) { return 2 }
        return 1
    }

    public static func of(_ s: String) -> Int { s.reduce(0) { $0 + of($1) } }

    /// Cuts `s` to at most `width` columns, ending with "…" when it was cut.
    public static func truncate(_ s: String, to width: Int) -> String {
        guard of(s) > width else { return s }
        guard width > 1 else { return width == 1 ? "…" : "" }
        var out = ""; var used = 0
        for c in s {
            let w = of(c)
            if used + w > width - 1 { break }
            out.append(c); used += w
        }
        return out + "…"
    }
}
