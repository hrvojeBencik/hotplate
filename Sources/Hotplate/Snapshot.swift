import AppKit
import SwiftUI
import HotplateCore

/// Developer aid: `Hotplate --snapshot <dir>` renders the main window and the menu bar
/// panel to PNG files (light and dark) using sample data, without needing screen recording.
enum Snapshot {
    static var requestedDirectory: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func run(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let model = SessionViewModel.shared
        // The Window scene opens the real main window shortly after launch; grab it, hide it, capture it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let window = NSApp.windows.first(where: { $0.contentView is NSHostingView<AnyView> || $0.title == "Hotplate" }) ?? NSApp.windows.first(where: { $0.isVisible }) else {
                FileHandle.standardError.write(Data("no main window found\n".utf8)); exit(1)
            }
            window.alphaValue = 0.01  // 0 would stop CoreAnimation from rendering the layers
            window.setContentSize(NSSize(width: 960, height: 600))
            capture(window: window, appearance: .darkAqua, to: "\(dir)/main-dark.png") {
                capture(window: window, appearance: .aqua, to: "\(dir)/main-light.png") {
                    model.state = .failed("flutter exited with code 1"); model.log("flutter exited with code 1", .error)
                    capture(window: window, appearance: .darkAqua, to: "\(dir)/main-failed-dark.png") {
                        model.state = .running
                        renderPanel(model: model, appearance: .darkAqua, to: "\(dir)/menubar-dark.png") {
                            renderPanel(model: model, appearance: .aqua, to: "\(dir)/menubar-light.png") { exit(0) }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private static func capture(window: NSWindow, appearance: NSAppearance.Name, to path: String, then: @escaping () -> Void) {
        window.appearance = NSAppearance(named: appearance)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let frame = window.contentView?.superview, let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { then(); return }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            write(rep, to: path)
            then()
        }
    }

    @MainActor
    private static func renderPanel(model: SessionViewModel, appearance: NSAppearance.Name, to path: String, then: @escaping () -> Void) {
        let hosting = NSHostingView(rootView: MenuBarPanel().environment(model).background(Color(nsColor: .windowBackgroundColor)))
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.setContentSize(size)
        window.alphaValue = 0.01  // 0 would stop CoreAnimation from rendering the layers
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let content = window.contentView?.superview, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: rep)
                write(rep, to: path)
            }
            window.close()
            then()
        }
    }

    private static func write(_ rep: NSBitmapImageRep, to path: String) {
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            FileHandle.standardError.write(Data("wrote \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))\n".utf8))
        }
    }
}

extension SessionViewModel {
    /// A populated model for previews and snapshots; never touches the real defaults.
    @MainActor
    static func preview(state: SessionState = .running) -> SessionViewModel {
        let defaults = UserDefaults(suiteName: "com.hrvojebencik.hotplate.preview")!
        defaults.removePersistentDomain(forName: "com.hrvojebencik.hotplate.preview")
        let m = SessionViewModel(store: ProjectStore(defaults: defaults))
        m.clearLogs()
        m.project = Project(path: "/Users/me/Projects/Lootique/lootique", name: "lootique")
        m.store.recents = [m.project!, Project(path: "/Users/me/Projects/Usput/usput", name: "usput")]
        m.devices = [
            FlutterDevice(id: "699E", name: "iPhone 18 Pro", targetPlatform: "ios", emulator: true, isSupported: true),
            FlutterDevice(id: "chrome", name: "Chrome", targetPlatform: "web-javascript", emulator: false, isSupported: true),
        ]
        m.selectedDeviceId = "699E"
        m.launchConfigs = [LaunchConfig(name: "[DEV] Lootique", args: ["--flavor", "development"]), LaunchConfig(name: "Lootique", args: ["--flavor", "production"])]
        m.extraArgs = "--flavor development --target lib/flavors/main_development.dart --dart-define-from-file env-dev.json"
        m.selectedLaunchConfigName = "[DEV] Lootique"
        m.state = state
        m.log("$ flutter run --machine -d 699E --flavor development --target lib/flavors/main_development.dart", .info)
        m.log("Launching lib/flavors/main_development.dart on iPhone 18 Pro in debug mode...", .normal)
        m.log("Running pod install...", .normal)
        m.log("Running Xcode build...", .normal)
        m.log("Xcode build done.                                           38.2s", .normal)
        m.log("The Dart VM service is listening on http://127.0.0.1:53210/abc=/", .normal)
        m.log("App started. Auto reload is on.", .success)
        m.log("flutter: [Posthog] Client initialised", .normal)
        m.log("Change detected in lib/ → hot reload", .info)
        m.log("Hot reload done in 412 ms. Reloaded 3 of 1284 libraries in 397ms.", .success)
        m.log("Another exception was thrown: RenderFlex overflowed by 24 pixels on the bottom.", .error)
        m.log("#0      TaskCard.build (package:lootique/features/tasks/presentation/widgets/task_card.dart:118:14)", .error)
        m.log("The following plugins do not support Swift Package Manager for ios:", .warning)
        m.log("  - posthog_flutter", .warning)
        m.log("Change detected in lib/ → hot reload", .info)
        m.log("Hot reload done in 388 ms. Reloaded 1 of 1284 libraries in 371ms.", .success)
        if case .failed(let msg) = state { m.log(msg, .error) }
        return m
    }
}
