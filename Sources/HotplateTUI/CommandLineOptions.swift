import HotplateCore

public struct CommandLineOptions: Equatable, Sendable {
    public struct ParseError: Error, Equatable {
        public let message: String
    }

    public var path: String?
    public var overrides = SessionOverrides()
    public var noRun = false
    public var flutterPath: String?
    public var showHelp = false
    public var showVersion = false

    public init() {}

    public static func parse(_ args: [String]) throws -> CommandLineOptions {
        var o = CommandLineOptions()
        var i = 0
        func value(for flag: String) throws -> String {
            i += 1
            guard i < args.count, !args[i].hasPrefix("-") else { throw ParseError(message: "\(flag) needs a value") }
            return args[i]
        }
        while i < args.count {
            let a = args[i]
            switch a {
            case "--":
                let rest = Array(args[(i + 1)...])
                if !rest.isEmpty { o.overrides.args = ArgumentSplitter.join(rest) }
                return o
            case "-d", "--device": o.overrides.deviceQuery = try value(for: a)
            case "-c", "--config": o.overrides.configName = try value(for: a)
            case "--no-run": o.noRun = true
            case "--no-auto-reload": o.overrides.autoReload = false
            case "--flutter": o.flutterPath = try value(for: a)
            case "-h", "--help": o.showHelp = true
            case "--version": o.showVersion = true
            default:
                if a.hasPrefix("-") { throw ParseError(message: "unknown option \(a)") }
                guard o.path == nil else { throw ParseError(message: "unexpected argument \(a)") }
                o.path = a
            }
            i += 1
        }
        return o
    }

    public static let usage = """
    Usage: hotplate [path] [options] [-- <flutter run arguments>]

    Runs a Flutter app with hot reload on save, in your terminal.

    Options:
      -d, --device <id|name>   Device to run on (part of the name is enough)
      -c, --config <name>      Configuration from .vscode/launch.json
          --no-run             Open without starting the app
          --no-auto-reload     Don't hot reload on save in this session
          --flutter <path>     Path to the flutter executable
      -h, --help               Show this help
          --version            Show the version

    Options apply to this session only. Choices made inside hotplate are remembered per project.
    Press ? inside hotplate for keyboard shortcuts.

    """
}
