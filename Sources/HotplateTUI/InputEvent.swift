public enum Key: Hashable, Sendable {
    case char(Character)
    /// Ctrl plus a lowercase letter, e.g. `.ctrl("c")`.
    case ctrl(Character)
    case enter, escape, backspace, tab, up, down, left, right, home, end, pageUp, pageDown, delete
}

public enum MouseButton: Equatable, Sendable { case left, wheelUp, wheelDown, other }

public struct MouseEvent: Equatable, Sendable {
    public let button: MouseButton
    /// 0-based column and row.
    public let x: Int
    public let y: Int
    public let pressed: Bool

    public init(button: MouseButton, x: Int, y: Int, pressed: Bool) {
        self.button = button; self.x = x; self.y = y; self.pressed = pressed
    }
}

public enum InputEvent: Equatable, Sendable {
    case key(Key)
    case mouse(MouseEvent)
    case paste(String)
}
