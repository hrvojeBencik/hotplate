/// Splits a free-form argument string into argv tokens, honoring single and
/// double quotes and backslash escapes (outside single quotes).
public enum ArgumentSplitter {
    public static func split(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuote: Character? = nil
        var hasToken = false
        var escape = false
        for ch in input {
            if escape { current.append(ch); escape = false; hasToken = true; continue }
            if ch == "\\" && inQuote != "'" { escape = true; continue }
            if let q = inQuote {
                if ch == q { inQuote = nil } else { current.append(ch) }
                continue
            }
            if ch == "\"" || ch == "'" { inQuote = ch; hasToken = true; continue }
            if ch.isWhitespace {
                if hasToken { result.append(current); current = ""; hasToken = false }
                continue
            }
            current.append(ch); hasToken = true
        }
        if hasToken { result.append(current) }
        return result
    }
}
