import Foundation

/// Turns raw terminal bytes into key, mouse and paste events. Incomplete sequences wait for the next `feed`.
public struct InputDecoder {
    private static let pasteEnd: [UInt8] = Array("\u{1B}[201~".utf8)
    private var buffer: [UInt8] = []
    private var pasting = false
    private var pasteBytes: [UInt8] = []

    public init() {}

    /// A lone ESC is either the Escape key or the start of a sequence; the caller flushes it after a short pause.
    public var hasPendingEscape: Bool { !pasting && buffer == [0x1B] }

    public mutating func feed(_ bytes: [UInt8]) -> [InputEvent] {
        buffer += bytes
        var events: [InputEvent] = []
        while !buffer.isEmpty {
            if pasting {
                guard let end = indexOf(Self.pasteEnd) else {
                    // Keep a possible partial terminator for the next read.
                    let keep = min(buffer.count, Self.pasteEnd.count - 1)
                    pasteBytes += buffer.dropLast(keep)
                    buffer = Array(buffer.suffix(keep))
                    break
                }
                pasteBytes += buffer[..<end]
                buffer.removeFirst(end + Self.pasteEnd.count)
                pasting = false
                events.append(.paste(String(decoding: pasteBytes, as: UTF8.self)))
                pasteBytes = []
                continue
            }
            guard let (event, used) = decodeOne() else { break }
            buffer.removeFirst(used)
            if let event { events.append(event) }
        }
        return events
    }

    public mutating func flushEscape() -> [InputEvent] {
        guard hasPendingEscape else { return [] }
        buffer.removeAll()
        return [.key(.escape)]
    }

    /// One event (or nil for ignored bytes) and how many bytes it used; nil when more bytes are needed.
    private mutating func decodeOne() -> (InputEvent?, Int)? {
        let b = buffer[0]
        switch b {
        case 0x1B: return decodeEscape()
        case 0x0D, 0x0A: return (.key(.enter), 1)
        case 0x09: return (.key(.tab), 1)
        case 0x7F, 0x08: return (.key(.backspace), 1)
        case 0x01...0x1A: return (.key(.ctrl(Character(UnicodeScalar(b + 0x60)))), 1)
        case 0x00, 0x1C...0x1F: return (nil, 1)
        default: return decodeUTF8()
        }
    }

    private mutating func decodeEscape() -> (InputEvent?, Int)? {
        guard buffer.count >= 2 else { return nil }
        switch buffer[1] {
        case UInt8(ascii: "["): return decodeCSI()
        case UInt8(ascii: "O"):
            guard buffer.count >= 3 else { return nil }
            let key: Key? = switch buffer[2] {
            case UInt8(ascii: "A"): .up
            case UInt8(ascii: "B"): .down
            case UInt8(ascii: "C"): .right
            case UInt8(ascii: "D"): .left
            case UInt8(ascii: "H"): .home
            case UInt8(ascii: "F"): .end
            default: nil
            }
            return (key.map { .key($0) }, 3)
        default:
            // ESC ESC, or Alt+key: report Escape and decode the rest separately.
            return (.key(.escape), 1)
        }
    }

    private mutating func decodeCSI() -> (InputEvent?, Int)? {
        var i = 2
        while i < buffer.count, (0x20...0x3F).contains(buffer[i]) { i += 1 }
        guard i < buffer.count else { return nil }
        let final = buffer[i]
        guard (0x40...0x7E).contains(final) else { return (nil, i) }
        let params = String(decoding: buffer[2..<i], as: UTF8.self)
        let used = i + 1
        if params.hasPrefix("<"), final == UInt8(ascii: "M") || final == UInt8(ascii: "m") {
            return (Self.mouse(params: String(params.dropFirst()), pressed: final == UInt8(ascii: "M")), used)
        }
        let first = params.split(separator: ";").first.flatMap { Int($0) }
        switch final {
        case UInt8(ascii: "A"): return (.key(.up), used)
        case UInt8(ascii: "B"): return (.key(.down), used)
        case UInt8(ascii: "C"): return (.key(.right), used)
        case UInt8(ascii: "D"): return (.key(.left), used)
        case UInt8(ascii: "H"): return (.key(.home), used)
        case UInt8(ascii: "F"): return (.key(.end), used)
        case UInt8(ascii: "~"):
            switch first {
            case 1, 7: return (.key(.home), used)
            case 4, 8: return (.key(.end), used)
            case 3: return (.key(.delete), used)
            case 5: return (.key(.pageUp), used)
            case 6: return (.key(.pageDown), used)
            case 200: pasting = true; return (nil, used)
            default: return (nil, used)
            }
        default: return (nil, used)
        }
    }

    private static func mouse(params: String, pressed: Bool) -> InputEvent? {
        let parts = params.split(separator: ";").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let code = parts[0]
        if code & 32 != 0 { return nil }
        let button: MouseButton = switch code & ~(4 | 8 | 16) {
        case 0: .left
        case 64: .wheelUp
        case 65: .wheelDown
        default: .other
        }
        return .mouse(MouseEvent(button: button, x: parts[1] - 1, y: parts[2] - 1, pressed: pressed))
    }

    private func decodeUTF8() -> (InputEvent?, Int)? {
        let b = buffer[0]
        let length = b < 0x80 ? 1 : b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : b >= 0xC0 ? 2 : 1
        guard buffer.count >= length else { return nil }
        guard let c = String(bytes: Array(buffer[0..<length]), encoding: .utf8)?.first else { return (nil, length) }
        return (.key(.char(c)), length)
    }

    private func indexOf(_ needle: [UInt8]) -> Int? {
        guard buffer.count >= needle.count else { return nil }
        for i in 0...(buffer.count - needle.count) where Array(buffer[i..<(i + needle.count)]) == needle { return i }
        return nil
    }
}
