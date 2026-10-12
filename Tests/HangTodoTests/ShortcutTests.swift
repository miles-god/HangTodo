import AppKit
import Carbon
import XCTest
@testable import HangTodo

final class ShortcutTests: XCTestCase {
    func testDefaultIsOptionT() {
        withDefaults { defaults in
            XCTAssertEqual(Shortcut.load(from: defaults), Shortcut.standard)
            XCTAssertEqual(Shortcut.standard.keyCode, kVK_ANSI_T)
            XCTAssertEqual(Shortcut.standard.modifiers, .option)
            XCTAssertEqual(Shortcut.standard.carbonModifiers, optionKey)
            XCTAssertEqual(Shortcut.standard.display, "⌥T")
        }
    }

    func testChangedShortcutAndRemovalSurviveNewPreferencesInstance() {
        withDefaults { defaults in
            let custom = Shortcut(keyCode: kVK_ANSI_R, modifiers: [.command, .option, .shift], key: "r")
            Shortcut.save(custom, to: defaults)
            let reopened = UserDefaults(suiteName: defaultsSuite)!
            XCTAssertEqual(Shortcut.load(from: reopened), custom)
            XCTAssertEqual(Shortcut.load(from: reopened)?.carbonModifiers, cmdKey | optionKey | shiftKey)
            Shortcut.save(nil, to: reopened)
            XCTAssertNil(Shortcut.load(from: UserDefaults(suiteName: defaultsSuite)!))
        }
    }

    func testNumericPreferencesReloadAndMalformedPreferencesUseDefault() {
        withDefaults { defaults in
            defaults.set(["keyCode": kVK_ANSI_Y, "modifiers": Int(NSEvent.ModifierFlags.control.rawValue), "key": "y"], forKey: "shortcut")
            XCTAssertEqual(Shortcut.load(from: defaults), Shortcut(keyCode: kVK_ANSI_Y, modifiers: .control, key: "y"))
            defaults.set(["keyCode": "broken", "modifiers": 0, "key": "t"], forKey: "shortcut")
            XCTAssertEqual(Shortcut.load(from: defaults), .standard)
            defaults.set(["keyCode": 100_000, "modifiers": 0, "key": "t"], forKey: "shortcut")
            XCTAssertEqual(Shortcut.load(from: defaults), .standard)
        }
    }

    func testOptionRecordingUsesPhysicalKeyAndDropsCapsLock() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.option, .capsLock], timestamp: 0, windowNumber: 0, context: nil,
            characters: "†", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: UInt16(kVK_ANSI_T)))
        XCTAssertEqual(Shortcut(event: event), .standard)
        let plain = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: UInt16(kVK_ANSI_T)))
        XCTAssertNil(Shortcut(event: plain))
    }

    private var defaultsSuite = ""
    private func withDefaults(_ check: (UserDefaults) -> Void) {
        defaultsSuite = "HangTodoShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        check(defaults)
    }
}
