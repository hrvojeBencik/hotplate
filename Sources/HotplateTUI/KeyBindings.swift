public enum Action: Equatable, Sendable {
    case enter, reload, restart, stop, quit
    case devices, configs, editArgs, toggleAutoReload, openProject, chooseEditor, projects
    case jumpToLink, previousLink, nextLink, copyLine, copyAll
    case search, nextMatch, previousMatch
    case lineUp, lineDown, pageUp, pageDown, halfPageUp, halfPageDown, top, bottom, toggleFollow
    case clearLog, cancel, redraw, help
}

public struct KeyBinding: Sendable {
    public let keys: [Key]
    public let keyLabel: String
    public let action: Action
    /// Short label for the footer; nil keeps the binding out of the footer.
    public let footerLabel: String?
    public let help: String

    init(_ keys: [Key], _ keyLabel: String, _ action: Action, _ footerLabel: String?, _ help: String) {
        self.keys = keys; self.keyLabel = keyLabel; self.action = action; self.footerLabel = footerLabel; self.help = help
    }
}

public struct FooterItem: Equatable, Sendable {
    public let key: String
    public let label: String
}

/// The single source of truth for normal-mode keys; the footer and the help screen are generated from it.
public enum KeyBindings {
    public static let normal: [KeyBinding] = [
        KeyBinding([.enter], "⏎", .enter, "run", "Run, or open the selected line's file"),
        KeyBinding([.char("r")], "r", .reload, "reload", "Hot reload"),
        KeyBinding([.char("R")], "R", .restart, "restart", "Hot restart"),
        KeyBinding([.char("s")], "s", .stop, "stop", "Stop the app"),
        KeyBinding([.char("q"), .ctrl("c")], "q", .quit, nil, "Stop and quit (Ctrl+C twice kills flutter)"),
        KeyBinding([.char("d")], "d", .devices, "device", "Choose device (Ctrl+R in the list refreshes)"),
        KeyBinding([.char("c")], "c", .configs, "config", "Choose launch.json configuration"),
        KeyBinding([.char("a")], "a", .editArgs, "args", "Edit run arguments"),
        KeyBinding([.char("A")], "A", .toggleAutoReload, "auto", "Reload on save on/off"),
        KeyBinding([.char("e")], "e", .openProject, "editor", "Open the project in your editor"),
        KeyBinding([.char("E")], "E", .chooseEditor, nil, "Choose the editor"),
        KeyBinding([.char("p")], "p", .projects, nil, "Recent projects"),
        KeyBinding([.char("o")], "o", .jumpToLink, "link", "Select the newest error or file link"),
        KeyBinding([.char("[")], "[", .previousLink, nil, "Previous file link"),
        KeyBinding([.char("]")], "]", .nextLink, nil, "Next file link"),
        KeyBinding([.char("y")], "y", .copyLine, nil, "Copy the selected line"),
        KeyBinding([.char("Y")], "Y", .copyAll, nil, "Copy the whole log"),
        KeyBinding([.char("/")], "/", .search, "find", "Search the log"),
        KeyBinding([.char("n")], "n", .nextMatch, nil, "Next match"),
        KeyBinding([.char("N")], "N", .previousMatch, nil, "Previous match"),
        KeyBinding([.char("k"), .up], "k ↑", .lineUp, nil, "Scroll up, or move the selection"),
        KeyBinding([.char("j"), .down], "j ↓", .lineDown, nil, "Scroll down, or move the selection"),
        KeyBinding([.pageUp], "PgUp", .pageUp, nil, "Page up"),
        KeyBinding([.pageDown], "PgDn", .pageDown, nil, "Page down"),
        KeyBinding([.ctrl("u")], "^U", .halfPageUp, nil, "Half a page up"),
        KeyBinding([.ctrl("d")], "^D", .halfPageDown, nil, "Half a page down"),
        KeyBinding([.char("g"), .home], "g", .top, nil, "Top of the log"),
        KeyBinding([.char("G"), .end], "G", .bottom, nil, "Bottom, and follow new lines"),
        KeyBinding([.char("f")], "f", .toggleFollow, nil, "Follow new lines on/off"),
        KeyBinding([.char("K")], "K", .clearLog, nil, "Clear the log"),
        KeyBinding([.escape], "Esc", .cancel, nil, "Clear the selection, then the search"),
        KeyBinding([.ctrl("l")], "^L", .redraw, nil, "Redraw the screen"),
        KeyBinding([.char("?")], "?", .help, "help", "Show this help"),
    ]

    public static func action(for key: Key) -> Action? {
        normal.first { $0.keys.contains(key) }?.action
    }

    /// Footer entries that fit in `width` columns (rendered as " k label  k label …"), always ending with "? help".
    public static func footerItems(width: Int, isRunning: Bool) -> [FooterItem] {
        let order: [Action] = isRunning
            ? [.stop, .reload, .restart, .devices, .configs, .editArgs, .openProject, .jumpToLink, .search, .toggleAutoReload]
            : [.enter, .devices, .configs, .editArgs, .openProject, .jumpToLink, .search, .toggleAutoReload]
        let help = FooterItem(key: "?", label: "help")
        var used = 1 + CharWidth.of("\(help.key) \(help.label)")
        var items: [FooterItem] = []
        for action in order {
            guard let b = normal.first(where: { $0.action == action }), let label = b.footerLabel else { continue }
            let w = CharWidth.of("\(b.keyLabel) \(label)") + 2
            if used + w > width { break }
            items.append(FooterItem(key: b.keyLabel, label: label))
            used += w
        }
        return items + [help]
    }
}
