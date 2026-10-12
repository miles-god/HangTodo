import AppKit
import XCTest
@testable import HangTodo

final class StatusMenuTests: XCTestCase {
    @MainActor
    func testMenuClosesOnApplicationSwitchEvenWhenLineIsHidden() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let menu = TrackingMenu()
        let delegate = AppDelegate(store: TaskStore(fileURL: folder.appendingPathComponent("tasks.json")), menu: menu)
        delegate.menuWillOpen(menu)
        delegate.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
        XCTAssertEqual(menu.cancellations, 1)
        delegate.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
        XCTAssertEqual(menu.cancellations, 1)
    }

    @MainActor
    func testClosedOrUnrelatedMenuIsNotCancelled() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let menu = TrackingMenu()
        let delegate = AppDelegate(store: TaskStore(fileURL: folder.appendingPathComponent("tasks.json")), menu: menu)
        delegate.menuWillOpen(menu)
        delegate.menuDidClose(menu)
        delegate.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
        XCTAssertEqual(menu.cancellations, 0)
        delegate.menuWillOpen(NSMenu())
        delegate.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
        XCTAssertEqual(menu.cancellations, 0)
    }
}

private final class TrackingMenu: NSMenu {
    var cancellations = 0
    override func cancelTracking() { cancellations += 1 }
}
