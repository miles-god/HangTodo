import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private var languageSubscription: AnyCancellable?

    func show(onShortcut: @escaping () -> Void, onLogin: @escaping (Bool) -> Void, onCategories: @escaping () -> Void) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("设置")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(onShortcut: onShortcut, onLogin: onLogin, onCategories: onCategories))
        self.window = window
        languageSubscription = AppPreferences.shared.$language.dropFirst().receive(on: RunLoop.main)
            .sink { [weak window] _ in window?.title = L("设置") }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject private var preferences = AppPreferences.shared
    var onShortcut: () -> Void
    var onLogin: (Bool) -> Void
    var onCategories: () -> Void

    var body: some View {
        Form {
            Section {
                Picker(L("语言"), selection: $preferences.language) {
                    ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
                }
                Text(L("界面语言立即生效。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("外观")) {
                Picker(L("便签大小"), selection: $preferences.cardSize) {
                    ForEach(Layout.Size.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section(L("显示与启动")) {
                Toggle(L("鼠标停在菜单栏时展开"), isOn: $preferences.opensFromMenuBar)
                Toggle(L("在全屏应用上显示"), isOn: $preferences.showsOverFullScreen)
                Toggle(L("登录时启动"), isOn: Binding(get: { preferences.launchAtLogin }, set: onLogin))
                Text(L("鼠标离开时保持展开；点击空白或切换窗口时收起。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("快捷键")) {
                HStack {
                    Text(Shortcut.current?.display ?? L("未设置"))
                    Spacer()
                    Button(L("更改…"), action: onShortcut)
                }
            }
            Section {
                Button(L("管理分类…"), action: onCategories)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 520)
        .environment(\.locale, preferences.language.locale)
    }
}
