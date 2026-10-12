import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store: TaskStore
    private let line = Line()
    private let editor = TaskEditor()
    private let categoryManager = CategoryManager()
    private let settings = SettingsWindow()
    private let preferences = AppPreferences.shared
    private var panel: LinePanel!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var cancellables = Set<AnyCancellable>()
    private var mouseTimer: Timer?
    private var clickMonitors: [Any] = []
    private var hotZoneSince: Date?
    private var menuBarSuppressed = false
    private var trackingMenus = 0
    private var statusMenuOpen = false
    private let statusMenu: NSMenu
    private var modalOpen = false
    private var windowTracker = WindowSwitchTracker()
    private var lastWindowCheck = Date.distantPast

    init(store: TaskStore? = nil, menu: NSMenu = NSMenu()) {
        self.store = store ?? TaskStore()
        self.statusMenu = menu
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = LineView(store: store, line: line,
            onAdd: { [weak self] in self?.edit(nil) },
            onEdit: { [weak self] in self?.edit($0) },
            onManageCategories: { [weak self] in self?.manageCategories() },
            onDelete: { [weak self] in self?.delete($0) })
        let host = LineHostingView(rootView: view)
        host.sizingOptions = []
        panel = LinePanel(content: TaskDropView(content: host, store: store, line: line))
        updateLayout()
        panel.onScroll = { [weak self] event in
            let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            self?.line.scroll(by: event.hasPreciseScrollingDeltas ? -delta : -delta * 12)
        }
        registerShortcut()
        setUpStatusItem()
        watchBlankClicks()

        store.$tasks.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLayout() }.store(in: &cancellables)
        Publishers.CombineLatest3(store.$selectedCategoryID, store.$selectedQuadrant, store.$showingCompleted)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.line.scroll = 0
                self?.updateLayout()
            }.store(in: &cancellables)
        line.$scroll.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizePanel() }.store(in: &cancellables)
        preferences.$cardSize.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateLayout() }.store(in: &cancellables)
        preferences.$language.receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.panel.title = L("HangTodo · 待办晾衣绳")
                self?.statusItem.button?.toolTip = L("HangTodo · 待办晾衣绳")
                self?.updateLayout()
            }.store(in: &cancellables)
        preferences.$showsOverFullScreen.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let screen = self.panel.screen else { return }
                if FullScreen.blocksLine(on: screen) { self.hide() }
            }.store(in: &cancellables)
        store.$errorMessage.compactMap { $0 }.receive(on: RunLoop.main)
            .sink { [weak self] message in self?.showError(message) }.store(in: &cancellables)

        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackingMenus += 1 }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { self.trackingMenus = max(0, self.trackingMenus - 1) } }
        }
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLayout(on: LinePanel.screenUnderPointer()) }
        }
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self?.dismissStatusMenu()
                self?.hide()
            }
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(revealExistingInstance),
            name: SingleInstance.revealNotification, object: SingleInstance.identifier)
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
        #if DEBUG
        if CommandLine.arguments.contains("--ui-test-settings") { showSettings() }
        else { show() }
        #else
        show()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        mouseTimer?.invalidate()
        clickMonitors.forEach(NSEvent.removeMonitor)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func applicationDidResignActive(_ notification: Notification) { dismissStatusMenu() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        #if DEBUG
        if CommandLine.arguments.contains("--ui-test-settings") { showSettings(); return true }
        #endif
        show()
        return true
    }

    @objc private func revealExistingInstance(_ notification: Notification) { show() }

    private func updateLayout(on chosenScreen: NSScreen? = nil) {
        guard let screen = chosenScreen ?? panel.screen ?? LinePanel.screenUnderPointer() else { return }
        line.visibleCount = max(1, Int((screen.visibleFrame.width - 100) / Layout.spacing))
        let tasks = store.visibleTasks
        line.itemCount = tasks.count
        let maximumHeight = max(120, screen.visibleFrame.height - 180)
        let metrics = Dictionary(uniqueKeysWithValues: tasks.map {
            ($0.id, TaskCardMetrics.measure($0, width: Layout.cardWidth, scale: Layout.size.scale, maximumHeight: maximumHeight))
        })
        if line.cardMetrics != metrics { line.cardMetrics = metrics }
        line.scroll(by: 0)
        resizePanel(on: screen)
    }

    private func resizePanel(on chosenScreen: NSScreen? = nil) {
        let tasks = store.visibleTasks
        let maxHeight = line.renderedIndices(count: tasks.count).map { line.cardMetrics[tasks[$0].id]?.height ?? 100 }.max() ?? 100
        let height = max(250, maxHeight + Layout.ropeTop + 25 + 14 + 52)
        if line.panelHeight != height { line.panelHeight = height }
        panel.placeOnScreen(chosenScreen ?? panel.screen, height: height)
    }

    private func show() {
        updateLayout(on: LinePanel.screenUnderPointer())
        guard let screen = panel.screen, !FullScreen.blocksLine(on: screen) else { return }
        windowTracker.baseline = ForegroundWindow.current()
        panel.orderFrontRegardless()
        line.revealed = true
    }

    private func hide() {
        guard line.revealed, line.draggingID == nil else { return }
        line.revealed = false
        line.showsCategories = false
        line.pointer = nil
        hotZoneSince = nil
        menuBarSuppressed = true
        panel.ignoresMouseEvents = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.line.revealed else { return }
            self.panel.orderOut(nil)
        }
    }

    private func toggle() { if line.revealed { hide() } else { show() } }

    static func menuBarBand(of screen: NSScreen) -> NSRect {
        var height = screen.frame.maxY - screen.visibleFrame.maxY
        if height < 1 { height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top) }
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
    }

    private func localPoint(_ mouse: NSPoint) -> CGPoint {
        let local = panel.convertPoint(fromScreen: mouse)
        return CGPoint(x: local.x, y: panel.frame.height - local.y)
    }

    private func watchBlankClicks() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.line.revealed else { return }
                let bounds = CGRect(origin: .zero, size: self.panel.frame.size)
                let controls = self.line.hitRects.values.map { $0.intersection(bounds) }.filter { !$0.isNull }
                if VisibilityPolicy.shouldHideForClick(at: self.localPoint(NSEvent.mouseLocation),
                    controls: controls, busy: self.line.draggingID != nil || self.trackingMenus > 0 || self.modalOpen) {
                    self.hide()
                }
            }
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.dismissStatusMenu() }
            handler(event)
        }) {
            clickMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            if let window = event.window, window.level.rawValue < NSWindow.Level.popUpMenu.rawValue {
                self?.dismissStatusMenu()
            }
            handler(event)
            return event
        }) {
            clickMonitors.append(monitor)
        }
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let now = Date()
        let screen = LinePanel.screenUnderPointer()
        let inMenuBar = screen.map { NSMouseInRect(mouse, Self.menuBarBand(of: $0), false) } ?? false
        if !inMenuBar { menuBarSuppressed = false }
        guard line.revealed else {
            if preferences.opensFromMenuBar, inMenuBar, !menuBarSuppressed, trackingMenus == 0,
               !modalOpen, let screen, !FullScreen.blocksLine(on: screen) {
                let since = hotZoneSince ?? now
                hotZoneSince = since
                if now.timeIntervalSince(since) >= 0.3 { hotZoneSince = nil; show() }
            } else { hotZoneSince = nil }
            return
        }
        let point = localPoint(mouse)
        if line.pointer != point { line.pointer = point }
        let overControl = line.hitRects.values.contains { $0.insetBy(dx: -4, dy: -4).contains(point) }
        panel.ignoresMouseEvents = line.draggingID == nil && !overControl
        if now.timeIntervalSince(lastWindowCheck) >= 0.2, trackingMenus == 0, !modalOpen, line.draggingID == nil {
            lastWindowCheck = now
            if windowTracker.changed(to: ForegroundWindow.current()) { hide() }
        }
    }

    private func edit(_ task: TodoTask?) {
        hide()
        editor.show(task: task, store: store) { [weak self] saved in
            guard let self else { return }
            self.store.selectedCategoryID = saved.categoryID
            if self.store.selectedQuadrant != nil { self.store.selectedQuadrant = saved.quadrant }
            self.store.showingCompleted = saved.isCompleted
            DispatchQueue.main.async {
                self.show()
                if let index = self.store.visibleTasks.firstIndex(where: { $0.id == saved.id }) { self.line.ensureVisible(index: index) }
            }
        }
    }

    private func manageCategories() { hide(); categoryManager.show(store: store) }

    private func delete(_ task: TodoTask) {
        modalOpen = true
        let alert = NSAlert()
        alert.messageText = L("删除这项任务？")
        alert.informativeText = F("“%@”将被删除。如果只是做完了，请选择标记完成。", task.title)
        alert.addButton(withTitle: L("取消"))
        alert.addButton(withTitle: L("删除任务"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { store.deleteTask(task.id) }
        modalOpen = false
    }

    private func showError(_ message: String) {
        store.errorMessage = nil
        modalOpen = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("操作未能完成")
        alert.informativeText = message
        alert.addButton(withTitle: L("好"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        modalOpen = false
    }

    private func registerShortcut() {
        hotKey = nil
        guard let shortcut = Shortcut.current else { return }
        hotKey = HotKey(shortcut) { [weak self] in self?.toggle() }
        if hotKey == nil { showError(F("快捷键 %@ 无法注册，请在设置中选择其他组合。", shortcut.display)) }
    }

    private func changeShortcut() {
        hotKey = nil
        ShortcutRecorder.shared.record { [weak self] result in
            guard let self else { return }
            if let result {
                if let shortcut = result {
                    guard let binding = HotKey(shortcut, action: { [weak self] in self?.toggle() }) else {
                        self.registerShortcut()
                        self.showError(F("快捷键 %@ 无法注册，请选择其他组合。原快捷键已保留。", shortcut.display))
                        return
                    }
                    self.hotKey = binding
                }
                Shortcut.current = result
            } else {
                self.registerShortcut()
            }
            self.preferences.shortcutRevision += 1
        }
    }

    private func showSettings() {
        hide()
        preferences.launchAtLogin = SMAppService.mainApp.status == .enabled
        settings.show(onShortcut: { [weak self] in self?.changeShortcut() },
            onLogin: { [weak self] enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch { self?.showError(F("无法更改登录启动设置：%@", error.localizedDescription)) }
                self?.preferences.launchAtLogin = SMAppService.mainApp.status == .enabled
            }, onCategories: { [weak self] in self?.manageCategories() })
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "HangTodo")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusMenu.autoenablesItems = false
        statusMenu.delegate = self
        statusItem.menu = statusMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(ClosureMenuItem(L("设置…"), key: ",") { [weak self] in self?.showSettings() })
        menu.addItem(ClosureMenuItem(L("退出 HangTodo"), key: "q") { NSApp.terminate(nil) })
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        statusMenuOpen = true
        hide()
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === statusMenu { statusMenuOpen = false }
    }

    private func dismissStatusMenu() {
        guard statusMenuOpen else { return }
        statusMenu.cancelTracking()
        statusMenuOpen = false
    }
}

private final class LineHostingView: NSHostingView<LineView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}
