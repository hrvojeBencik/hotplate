import AppKit
import SwiftUI
import HotplateCore

/// Installs `/usr/local/bin/hotplate` as a symlink to the tool inside this app, like VS Code's "Install 'code' command".
enum CommandLineInstaller {
    static let linkPath = "/usr/local/bin/hotplate"
    static var helperPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/hotplate").path }
    static var status: CommandLineToolStatus { CommandLineToolStatus.check(linkPath: linkPath, helperPath: helperPath) }

    @MainActor static func install() {
        guard status != .unavailable else {
            alert("The command line tool is not in this build", "It ships inside Hotplate.app built with scripts/build_app.sh.")
            return
        }
        if run(CommandLineToolStatus.installScript(helperPath: helperPath, linkPath: linkPath)) {
            alert("Installed the hotplate command", "Open a new terminal tab and run hotplate in a Flutter project. Press ? inside for shortcuts.")
        }
    }

    @MainActor static func remove() {
        if run(CommandLineToolStatus.removeScript(linkPath: linkPath)) { alert("Removed the hotplate command", "") }
    }

    /// Runs an AppleScript; false when it failed or the user cancelled the password prompt.
    @MainActor private static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return true }
        if (error[NSAppleScript.errorNumber] as? Int) != -128 {
            alert("Could not change the command line tool", error[NSAppleScript.errorMessage] as? String ?? "Unknown error")
        }
        return false
    }

    @MainActor private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

struct CommandLineToolRow: View {
    @State private var status = CommandLineInstaller.status

    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(status == .installed ? "Reinstall" : "Install") {
                CommandLineInstaller.install(); status = CommandLineInstaller.status
            }
            .disabled(status == .unavailable)
            if status != .notInstalled, status != .unavailable {
                Button("Remove") { CommandLineInstaller.remove(); status = CommandLineInstaller.status }
            }
        }
        Text("Run hotplate in a Flutter project folder. Press ? inside for shortcuts.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private var label: String {
        switch status {
        case .installed: return "Installed at \(CommandLineInstaller.linkPath)"
        case .notInstalled: return "Not installed"
        case .otherCopy(let path): return "\(CommandLineInstaller.linkPath) points to another copy (\(path))"
        case .unavailable: return "Not available in this build"
        }
    }
}
