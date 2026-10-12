import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    private let defaults: UserDefaults
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "appLanguage") } }
    @Published var cardSize: Layout.Size { didSet { defaults.set(cardSize.rawValue, forKey: "lineSize") } }
    @Published var opensFromMenuBar: Bool { didSet { defaults.set(!opensFromMenuBar, forKey: "menuBarRevealOff") } }
    @Published var showsOverFullScreen: Bool { didSet { defaults.set(showsOverFullScreen, forKey: "showOverFullScreen") } }
    @Published var launchAtLogin = false
    @Published var shortcutRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .chinese
        cardSize = Layout.Size(rawValue: defaults.string(forKey: "lineSize") ?? "") ?? .medium
        opensFromMenuBar = !defaults.bool(forKey: "menuBarRevealOff")
        showsOverFullScreen = defaults.bool(forKey: "showOverFullScreen")
    }
}
