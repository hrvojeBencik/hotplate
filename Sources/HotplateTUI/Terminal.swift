import Darwin

public enum TerminalError: Error { case notATerminal }

/// Raw mode, alternate screen, mouse and bracketed paste, with a restore that always runs on exit.
public final class Terminal {
    private static var active: Terminal?
    private var original = termios()
    private var isRaw = false

    public init() {}

    public static var isInteractive: Bool { isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1 }

    public func enter() throws {
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw TerminalError.notATerminal }
        var raw = original
        raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_cflag |= tcflag_t(CS8)
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
        withUnsafeMutableBytes(of: &raw.c_cc) { cc in
            cc[Int(VMIN)] = 1
            cc[Int(VTIME)] = 0
        }
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else { throw TerminalError.notATerminal }
        isRaw = true
        Terminal.active = self
        atexit { Terminal.active?.restore() }
        // Alternate screen, hidden cursor, click + SGR mouse reporting, bracketed paste.
        write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?1000h\u{1B}[?1006h\u{1B}[?2004h")
    }

    /// Safe to call more than once.
    public func restore() {
        guard isRaw else { return }
        isRaw = false
        write("\u{1B}[?2004l\u{1B}[?1006l\u{1B}[?1000l\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l")
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
    }

    public func write(_ s: String) {
        let bytes = Array(s.utf8)
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(STDOUT_FILENO, $0.baseAddress! + offset, bytes.count - offset) }
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return
            }
            offset += n
        }
    }

    public func size() -> TerminalSize {
        var ws = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 else {
            return TerminalSize(width: 80, height: 24)
        }
        return TerminalSize(width: Int(ws.ws_col), height: Int(ws.ws_row))
    }
}
