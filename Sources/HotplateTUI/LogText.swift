import Foundation

enum LogText {
    private static let csi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")
    private static let osc = try! NSRegularExpression(pattern: "\u{1B}\\].*?(\u{07}|\u{1B}\\\\)")
    private static let twoByteEscape = try! NSRegularExpression(pattern: "\u{1B}[@-Z\\\\^_]")
    private static let charsetEscape = try! NSRegularExpression(pattern: "\u{1B}[()].")

    /// Removes terminal escape sequences and control characters from app output; tabs become four spaces.
    static func sanitize(_ s: String) -> String {
        // Step 1: Remove escape sequences
        var stripped = s
        for regex in [csi, osc, twoByteEscape, charsetEscape] {
            stripped = regex.stringByReplacingMatches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped), withTemplate: "")
        }

        // Step 2: Handle carriage returns
        stripped = handleCarriageReturns(stripped)

        // Step 3: Convert tabs and filter control characters
        var out = ""
        for c in stripped {
            if c == "\t" { out += "    " }
            else if c.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) { out.append(c) }
        }
        return out
    }

    private static func handleCarriageReturns(_ s: String) -> String {
        var lines: [String] = []
        var current = ""
        var i = s.startIndex

        while i < s.endIndex {
            let c = s[i]
            if c == "\r" {
                let next = s.index(after: i)
                if next < s.endIndex {
                    // There's content after \r
                    if s[next] == "\n" {
                        // CRLF line ending: keep current line, skip both characters
                        lines.append(current)
                        current = ""
                        i = s.index(after: next)
                    } else {
                        // Bare \r with content after: discard current line, start over
                        current = ""
                        i = next
                    }
                } else {
                    // \r at end of string: ignore it
                    i = next
                }
            } else if c == "\n" {
                // LF line ending
                lines.append(current)
                current = ""
                i = s.index(after: i)
            } else {
                current.append(c)
                i = s.index(after: i)
            }
        }

        // Add final line if not empty
        if !current.isEmpty {
            lines.append(current)
        }

        return lines.joined(separator: "\n")
    }
}
