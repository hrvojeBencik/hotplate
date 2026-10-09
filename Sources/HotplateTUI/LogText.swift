import Foundation

enum LogText {
    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")

    /// Removes terminal escape sequences and control characters from app output; tabs become four spaces.
    static func sanitize(_ s: String) -> String {
        let stripped = ansi.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        var out = ""
        for c in stripped {
            if c == "\t" { out += "    " }
            else if c.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) { out.append(c) }
        }
        return out
    }
}
