import Foundation

/// Feeds stdin, resize and termination signals into `TUIApp` on the main queue.
@MainActor
public final class TerminalLoop {
    private let terminal: Terminal
    private let app: TUIApp
    private var decoder = InputDecoder()
    private var sources: [DispatchSourceProtocol] = []
    private var input: DispatchSourceRead?

    public init(terminal: Terminal, app: TUIApp) { self.terminal = terminal; self.app = app }

    public func start() {
        let input = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        input.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readInput() } }
        input.resume()
        self.input = input
        watch(SIGWINCH) { [weak self] in
            guard let self else { return }
            self.app.resize(to: self.terminal.size())
        }
        for sig in [SIGTERM, SIGHUP, SIGINT] { watch(sig) { [weak self] in self?.app.quit() } }
    }

    private func watch(_ sig: Int32, _ handler: @escaping @MainActor () -> Void) {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { handler() } }
        source.resume()
        sources.append(source)
    }

    private func readInput() {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(STDIN_FILENO, &buf, buf.count)
        if n == 0 {
            // The terminal went away: stop reading so EOF does not count as repeated quit requests.
            input?.cancel()
            app.quit()
            return
        }
        guard n > 0 else { return }
        for event in decoder.feed(Array(buf[0..<n])) { app.handle(event) }
        if decoder.hasPendingEscape {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for event in self.decoder.flushEscape() { self.app.handle(event) }
                }
            }
        }
    }
}
