import AppKit
import UniformTypeIdentifiers
import HotplateCore

/// The SwiftUI views keep their name for the model; the logic lives in `HotplateCore.Session`.
typealias SessionViewModel = Session

extension Session {
    static let shared: Session = Snapshot.requestedDirectory != nil ? preview() : makeAppSession()

    private static func makeAppSession() -> Session {
        let session = Session(store: ProjectStore(), hints: .gui)
        session.onError = { _ in NSSound.beep() }
        return session
    }

    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose a Flutter project folder (the one containing pubspec.yaml)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectProject(path: url.path)
    }

    func chooseEditorApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose the editor application"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.editorAppPath = url.path
        store.editorUseCustomCommand = false
    }
}
