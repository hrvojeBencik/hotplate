import Foundation
import HotplateCore
import HotplateTUI

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("hotplate: \(message)\n".utf8))
    exit(code)
}

// A dead reader (flutter, pbcopy) must not kill us with the terminal left raw; writes then fail with EPIPE.
signal(SIGPIPE, SIG_IGN)

let options: CommandLineOptions
do {
    options = try CommandLineOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    let message = (error as? CommandLineOptions.ParseError)?.message ?? "\(error)"
    FileHandle.standardError.write(Data("hotplate: \(message)\n\n\(CommandLineOptions.usage)".utf8))
    exit(2)
}
if options.showHelp { print(CommandLineOptions.usage, terminator: ""); exit(0) }
if options.showVersion { print("hotplate \(HotplateVersion.current)"); exit(0) }
guard Terminal.isInteractive else { fail("needs an interactive terminal", code: 2) }

let cwd = FileManager.default.currentDirectoryPath
let start: String = {
    guard let p = options.path else { return cwd }
    let expanded = (p as NSString).expandingTildeInPath
    return expanded.hasPrefix("/") ? expanded : (cwd as NSString).appendingPathComponent(expanded)
}()

let loop: TerminalLoop = MainActor.assumeIsolated {
    let store = ProjectStore()
    let projectPath = ProjectLocator.find(from: start)
    if projectPath == nil, store.recents.isEmpty { fail("no Flutter project found at or above \(start)", code: 1) }

    let session = Session(store: store, hints: .terminal, flutterPathOverride: options.flutterPath, restoreLastProject: false)
    session.overrides = options.overrides
    if let projectPath {
        session.selectProject(path: projectPath)
    } else {
        session.log("No Flutter project at or above \(start). Pick a recent project.", .warning)
    }

    let terminal = Terminal()
    do { try terminal.enter() } catch { fail("needs an interactive terminal", code: 2) }
    let app = TUIApp(session: session, size: terminal.size(), output: terminal.write, copy: Clipboard.copy,
                     exit: { code in terminal.restore(); exit(code) })
    let loop = TerminalLoop(terminal: terminal, app: app)
    loop.start()
    Task { await app.start(autoRun: !options.noRun) }
    return loop
}

withExtendedLifetime(loop) { RunLoop.main.run() }
