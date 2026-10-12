import AppKit
import Combine
import Carbon

/// A single global shortcut through the Carbon hot key API. Unlike a global
/// key monitor, it needs no Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var action: (() -> Void)?
    private static var handlerInstalled = false

    /// Nil when the combination cannot be registered, for example because
    /// another app already took it.
    init?(_ shortcut: Shortcut, action: @escaping () -> Void) {
        HotKey.action = action
        // One handler for the app, however many times the shortcut changes.
        if !HotKey.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.action?() }
                return noErr
            }, 1, &spec, nil, nil)
            HotKey.handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x5445_4E44), id: 1) // "TEND"
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.carbonModifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else { return nil }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}

/// The shortcut that shows and hides the line: ⌥T unless changed, or none.
struct Shortcut: Equatable {
    var keyCode: Int
    var modifiers: NSEvent.ModifierFlags
    /// The key as typed, for the menu: "t", " ", "1".
    var key: String

    static let standard = Shortcut(keyCode: kVK_ANSI_T, modifiers: .option, key: "t")

    private static let defaultsKey = "shortcut"

    /// The user's choice. Nil means no shortcut at all.
    static var current: Shortcut? {
        get { load(from: .standard) }
        set { save(newValue, to: .standard) }
    }

    static func load(from defaults: UserDefaults) -> Shortcut? {
        guard let saved = defaults.dictionary(forKey: defaultsKey) else { return standard }
        if saved.isEmpty { return nil }
        guard let code = saved["keyCode"] as? NSNumber, (0...Int(UInt16.max)).contains(code.intValue),
              let flags = saved["modifiers"] as? NSNumber, let key = saved["key"] as? String, !key.isEmpty else { return standard }
        return Shortcut(keyCode: code.intValue, modifiers: NSEvent.ModifierFlags(rawValue: flags.uintValue), key: key)
    }

    static func save(_ shortcut: Shortcut?, to defaults: UserDefaults) {
        defaults.set(shortcut.map {
            ["keyCode": $0.keyCode, "modifiers": NSNumber(value: $0.modifiers.rawValue), "key": $0.key] as [String: Any]
        } ?? [:], forKey: defaultsKey)
    }

    /// From a key press, if it makes a usable global shortcut: it needs
    /// Command, Control or Option, so typing alone never triggers it.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !flags.intersection([.command, .control, .option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return nil }
        self.init(keyCode: Int(event.keyCode), modifiers: flags, key: key)
    }

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    var carbonModifiers: Int {
        var carbon = 0
        if modifiers.contains(.command) { carbon |= cmdKey }
        if modifiers.contains(.control) { carbon |= controlKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        return carbon
    }

    /// As macOS writes it in menus: ⌃⌥⇧⌘ and the key.
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (key == " " ? L("空格") : key.uppercased())
    }
}

/// Asks for a new shortcut in a small window: the next key press with
/// Command, Control or Option becomes it. Escape cancels and Delete leaves
/// the line without a shortcut.
@MainActor
final class ShortcutRecorder: NSObject, NSWindowDelegate {
    static let shared = ShortcutRecorder()

    private var window: NSWindow?
    private var monitor: Any?
    private var done: ((Shortcut??) -> Void)?
    private var languageSubscription: AnyCancellable?

    /// Calls back with the new shortcut, `.some(nil)` for none, or nil if
    /// cancelled.
    func record(_ done: @escaping (Shortcut??) -> Void) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        self.done = done

        let title = NSTextField(labelWithString: L("按下新的快捷键"))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let hint = NSTextField(labelWithString: L("Escape 取消，Delete 移除快捷键。"))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 22, right: 28)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 100),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("更改快捷键")
        window.contentView = stack
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        languageSubscription = AppPreferences.shared.$language.dropFirst().receive(on: RunLoop.main).sink { [weak window, weak title, weak hint] _ in
            window?.title = L("更改快捷键")
            title?.stringValue = L("按下新的快捷键")
            hint?.stringValue = L("Escape 取消，Delete 移除快捷键。")
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  event.window === window || (event.window == nil && window.isKeyWindow) else { return event }
            let plain = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            if event.keyCode == UInt16(kVK_Escape) && plain {
                self.finish(nil)
            } else if (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) && plain {
                self.finish(.some(nil))
            } else if let shortcut = Shortcut(event: event) {
                self.finish(.some(shortcut))
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        finish(nil)
    }

    private func finish(_ result: Shortcut??) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        languageSubscription = nil
        let done = self.done
        self.done = nil
        window?.close()
        window = nil
        done?(result)
    }
}
