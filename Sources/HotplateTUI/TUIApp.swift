import Foundation
import Observation
import HotplateCore

/// The terminal front end: turns input into `Session` calls and draws the session into a screen buffer.
@MainActor
public final class TUIApp {
    public enum InputKind: Equatable, Sendable { case args, search }
    public enum Mode: Equatable, Sendable { case normal, picker, input(InputKind), help }

    public let session: Session
    public private(set) var mode: Mode = .normal
    public private(set) var viewport = LogViewport()
    public private(set) var picker: Picker?
    public private(set) var size: TerminalSize

    private var input = TextInput(text: "")
    private let output: (String) -> Void
    private let copy: (String) -> Void
    private let exit: (Int32) -> Void
    private let now: () -> Date
    private var renderer = Renderer()
    private var renderScheduled = false
    private var runAfterDevicePick = false
    /// Set while no project is open at start: the auto-run choice to apply once one is picked.
    private var startAfterProjectPick: Bool?
    private var quitRequestedAt: Date?
    private var quitting = false
    private var helpScroll = 0

    public init(session: Session, size: TerminalSize, output: @escaping (String) -> Void,
                copy: @escaping (String) -> Void, exit: @escaping (Int32) -> Void, now: @escaping () -> Date = Date.init) {
        self.session = session; self.size = size; self.output = output; self.copy = copy; self.exit = exit; self.now = now
    }

    // MARK: Start

    public func start(autoRun: Bool) async {
        render()
        guard session.project != nil else {
            startAfterProjectPick = autoRun
            openPicker(.project)
            return
        }
        await runStartup(autoRun: autoRun)
    }

    private func runStartup(autoRun: Bool) async {
        if case .needsDevice(let filter) = await session.startup(autoRun: autoRun) {
            runAfterDevicePick = autoRun
            openPicker(.device, filter: filter)
        }
        scheduleRender()
    }

    // MARK: Input

    public func handle(_ event: InputEvent) {
        defer { scheduleRender() }
        if event == .key(.ctrl("c")) { quit(); return }
        switch mode {
        case .help:
            handleHelp(event)
        case .picker:
            handlePicker(event)
        case .input(let kind):
            handleInput(event, kind: kind)
        case .normal:
            switch event {
            case .key(let key): if let action = KeyBindings.action(for: key) { perform(action) }
            case .mouse(let m): handleMouse(m)
            case .paste: break
            }
        }
    }

    func perform(_ action: Action) {
        switch action {
        case .enter:
            if let id = viewport.selectedLineId {
                openLink(onLine: id, link: nil)
            } else if session.selectedDevice == nil, session.project != nil, session.flutterPath != nil, !session.isRunning {
                runAfterDevicePick = true
                openPicker(.device)
            } else if session.canRun {
                Task { await session.run() }
            }
        case .reload: Task { await session.hotReload() }
        case .restart: Task { await session.hotRestart() }
        case .stop: Task { await session.stop() }
        case .quit: quit()
        case .devices: openPicker(.device)
        case .configs: openPicker(.config)
        case .editArgs: input = TextInput(text: session.extraArgs); mode = .input(.args)
        case .toggleAutoReload: session.setAutoReload(!session.autoReload)
        case .openProject: session.openInEditor()
        case .chooseEditor: openPicker(.editor)
        case .projects: openPicker(.project)
        case .jumpToLink: if let id = viewport.lastLinkLine() { viewport.select(lineId: id) }
        case .previousLink: if let id = viewport.linkLine(from: viewport.selectedLineId, forward: false) { viewport.select(lineId: id) }
        case .nextLink: if let id = viewport.linkLine(from: viewport.selectedLineId, forward: true) { viewport.select(lineId: id) }
        case .copyLine:
            if let id = viewport.selectedLineId, let e = viewport.entry(id) { copy(e.text) }
        case .copyAll:
            copy(session.logs.map { "\(LogPane.timeFormatter.string(from: $0.time))  \($0.text)" }.joined(separator: "\n"))
        case .search: input = TextInput(text: viewport.searchQuery ?? ""); mode = .input(.search)
        case .nextMatch: if let id = viewport.searchMatch(from: viewport.selectedLineId, forward: true) { viewport.select(lineId: id) }
        case .previousMatch: if let id = viewport.searchMatch(from: viewport.selectedLineId, forward: false) { viewport.select(lineId: id) }
        case .lineUp: viewport.selectedLineId != nil ? viewport.moveSelection(by: -1) : viewport.scroll(by: -1)
        case .lineDown: viewport.selectedLineId != nil ? viewport.moveSelection(by: 1) : viewport.scroll(by: 1)
        case .pageUp: viewport.scroll(by: -max(1, viewport.height - 1))
        case .pageDown: viewport.scroll(by: max(1, viewport.height - 1))
        case .halfPageUp: viewport.scroll(by: -max(1, viewport.height / 2))
        case .halfPageDown: viewport.scroll(by: max(1, viewport.height / 2))
        case .top: viewport.scrollToTop()
        case .bottom: viewport.select(lineId: nil); viewport.scrollToBottom()
        case .toggleFollow: viewport.setFollow(!viewport.follow)
        case .clearLog: session.clearLogs(); viewport.select(lineId: nil)
        case .cancel:
            if viewport.selectedLineId != nil { viewport.select(lineId: nil) } else { viewport.setSearch(nil) }
        case .redraw: renderer.invalidate()
        case .help: helpScroll = 0; mode = .help
        }
    }

    private func handleHelp(_ event: InputEvent) {
        let maxScroll = HelpOverlay.maxScroll(for: size)
        let page = max(1, size.height - 4)
        func scroll(by delta: Int) { helpScroll = min(maxScroll, max(0, helpScroll + delta)) }
        switch event {
        case .key(.up), .key(.char("k")): scroll(by: -1)
        case .key(.down), .key(.char("j")): scroll(by: 1)
        case .key(.pageUp): scroll(by: -page)
        case .key(.pageDown): scroll(by: page)
        case .mouse(let m):
            switch m.button {
            case .wheelUp: scroll(by: -1)
            case .wheelDown: scroll(by: 1)
            case .left where m.pressed: mode = .normal
            default: break
            }
        default: mode = .normal
        }
    }

    private func openLink(onLine id: Int, link: LogLink?) {
        guard let link = link ?? viewport.links(onLine: id).first else { return }
        session.openLogLink(location: link.location, line: link.line, column: link.column)
    }

    private func handleMouse(_ m: MouseEvent) {
        switch m.button {
        case .wheelUp: viewport.scroll(by: -3)
        case .wheelDown: viewport.scroll(by: 3)
        case .left where m.pressed:
            guard let hit = viewport.hit(row: m.y - Layout.logTop, column: m.x) else { return }
            viewport.select(lineId: hit.lineId)
            if let link = hit.link { openLink(onLine: hit.lineId, link: link) }
        default: break
        }
    }

    private func handleInput(_ event: InputEvent, kind: InputKind) {
        switch event {
        case .paste(let s):
            input.insert(s.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " "))
        case .key(let key):
            switch input.handle(key) {
            case .editing: break
            case .cancel: mode = .normal
            case .submit:
                mode = .normal
                switch kind {
                case .args:
                    session.setArgs(input.text)
                case .search:
                    viewport.setSearch(input.text)
                    if let id = viewport.searchMatch(from: nil, forward: false) { viewport.select(lineId: id) }
                }
            }
        case .mouse: break
        }
    }

    // MARK: Pickers

    private func openPicker(_ kind: PickerKind, filter: String = "") {
        if kind == .editor { session.refreshInstalledEditors() }
        picker = Picker(kind: kind, items: items(for: kind), filter: filter)
        mode = .picker
    }

    private func closePicker() {
        picker = nil
        mode = .normal
    }

    private func handlePicker(_ event: InputEvent) {
        guard var p = picker else { mode = .normal; return }
        switch event {
        case .key(.escape):
            runAfterDevicePick = false
            closePicker()
            return
        case .key(.enter):
            closePicker()
            if let item = p.selected { choose(item, in: p.kind) }
            return
        case .key(.up), .key(.ctrl("p")): p.move(by: -1)
        case .key(.down), .key(.ctrl("n")), .key(.tab): p.move(by: 1)
        case .key(.backspace): p.backspace()
        case .key(.ctrl("r")): if p.kind == .device { Task { await session.refreshDevices() } }
        case .key(.char(let c)): p.type(c)
        case .paste(let s): s.filter { !$0.isNewline }.forEach { p.type($0) }
        case .mouse(let m):
            switch m.button {
            case .wheelUp: p.move(by: -1)
            case .wheelDown: p.move(by: 1)
            case .left where m.pressed:
                if let index = p.itemIndex(atX: m.x, y: m.y, in: size) {
                    p.select(index: index)
                    closePicker()
                    if let item = p.selected { choose(item, in: p.kind) }
                    return
                }
                if !p.contains(x: m.x, y: m.y, in: size) { runAfterDevicePick = false; closePicker(); return }
            default: break
            }
        default: break
        }
        picker = p
    }

    private func choose(_ item: PickerItem, in kind: PickerKind) {
        switch kind {
        case .device:
            session.chooseDevice(id: item.id)
            if runAfterDevicePick {
                runAfterDevicePick = false
                Task { await session.run() }
            }
        case .config:
            session.chooseLaunchConfig(name: item.id.isEmpty ? nil : item.id)
        case .editor:
            session.editorSelection = item.id
        case .project:
            if let autoRun = startAfterProjectPick {
                startAfterProjectPick = nil
                session.selectProject(path: item.id)
                Task { await runStartup(autoRun: autoRun) }
            } else {
                session.switchProject(path: item.id)
            }
        }
    }

    private func items(for kind: PickerKind) -> [PickerItem] {
        switch kind {
        case .device:
            return session.devices.map {
                PickerItem(id: $0.id, title: $0.displayName, detail: $0.targetPlatform, isCurrent: $0.id == session.selectedDeviceId)
            }
        case .config:
            return session.launchConfigs.map {
                PickerItem(id: $0.name, title: $0.name, detail: ArgumentSplitter.join($0.flutterRunArguments),
                           isCurrent: $0.name == session.selectedLaunchConfigName)
            } + [PickerItem(id: "", title: "Custom (keep current args)", detail: session.extraArgs,
                            isCurrent: session.selectedLaunchConfigName == nil)]
        case .editor:
            let selection = session.editorSelection
            var list = session.installedEditors.map {
                PickerItem(id: $0.appPath, title: $0.name, detail: "", isCurrent: selection == $0.appPath)
            }
            if let other = session.otherEditor {
                list.append(PickerItem(id: other.appPath, title: other.name, detail: "", isCurrent: selection == other.appPath))
            }
            list.append(PickerItem(id: "custom", title: "Custom command", detail: session.store.editorCustomCommand,
                                   isCurrent: selection == "custom"))
            return list
        case .project:
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return session.store.recents.map { p in
                let shown = p.path.hasPrefix(home) ? "~" + p.path.dropFirst(home.count) : p.path
                return PickerItem(id: p.path, title: p.name, detail: String(shown), isCurrent: p.path == session.project?.path)
            }
        }
    }

    // MARK: Quit

    /// `q`, Ctrl+C or a signal: stop flutter cleanly, then exit. A second request within 2 s kills flutter.
    public func quit() {
        let t = now()
        if let first = quitRequestedAt, t.timeIntervalSince(first) <= 2 {
            session.forceQuit()
            exit(130)
            return
        }
        quitRequestedAt = t
        guard !quitting else { return }
        quitting = true
        Task {
            await session.shutdown()
            exit(0)
        }
    }

    // MARK: Drawing

    public func resize(to newSize: TerminalSize) {
        size = newSize
        renderer.invalidate()
        render()
    }

    public func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
            MainActor.assumeIsolated {
                self?.renderScheduled = false
                self?.render()
            }
        }
    }

    /// Draws now and re-renders whenever anything the frame read from `Session` changes.
    public func render() {
        let frame = withObservationTracking {
            compose()
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleRender() } }
        }
        output(renderer.render(frame))
    }

    public func compose() -> ScreenBuffer {
        var buf = ScreenBuffer(width: size.width, height: size.height)
        guard size.width >= Layout.minWidth, size.height >= Layout.minHeight else {
            buf.put("Terminal too small (min \(Layout.minWidth)×\(Layout.minHeight))", x: 0, y: 0)
            return buf
        }
        viewport.update(lines: session.logs, width: size.width, height: size.height - 4)
        StatusBar.draw(StatusInfo(project: session.project?.name, state: session.state, statusText: session.statusText,
                                  flutterMissing: session.flutterPath == nil,
                                  device: session.selectedDevice?.displayName ?? session.selectedDeviceId,
                                  config: session.selectedLaunchConfigName, autoReload: session.autoReload), into: &buf)
        let rule = String(repeating: "─", count: size.width)
        buf.put(rule, x: 0, y: 1, style: Style(fg: .gray))
        buf.put(rule, x: 0, y: size.height - 2, style: Style(fg: .gray))
        LogPane.draw(viewport, into: &buf, top: Layout.logTop)
        if case .input(let kind) = mode {
            input.draw(into: &buf, y: size.height - 1, prompt: kind == .args ? "args: " : "/")
        } else {
            FooterBar.draw(KeyBindings.footerItems(width: size.width, isRunning: session.isRunning), into: &buf, y: size.height - 1)
        }
        if mode == .picker, var p = picker {
            p.setItems(items(for: p.kind))
            picker = p
            p.draw(into: &buf, busy: p.kind == .device && session.isLoadingDevices)
        }
        if mode == .help { HelpOverlay.draw(into: &buf, scroll: min(helpScroll, HelpOverlay.maxScroll(for: size))) }
        return buf
    }
}
