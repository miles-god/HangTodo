import AppKit
import XCTest
@testable import HangTodo

final class InteractionTests: XCTestCase {
    private func task(notes: String = "") -> TodoTask {
        TodoTask(id: UUID(), title: "Small task", notes: notes, categoryID: TaskCategory.workID,
                 quadrant: .importantUrgent, createdAt: Date())
    }

    func testCardHeightTracksWrappedLinesAndCapsVeryLongNotes() {
        func measure(_ notes: String, width: CGFloat = 226) -> TaskCardMetrics {
            .measure(task(notes: notes), width: width, scale: 1, maximumHeight: 400)
        }
        let empty = measure("")
        XCTAssertEqual(empty, measure("  \n "))
        XCTAssertLessThan(empty.height, 70)
        let one = measure("One line"), three = measure("One\nTwo\nThree")
        XCTAssertEqual(one.noteLines, 1)
        XCTAssertEqual(three.noteLines, 3)
        XCTAssertGreaterThan(one.height, empty.height)
        XCTAssertGreaterThan(three.height, one.height)
        let wrapped = measure(String(repeating: "备注需要自动换行", count: 12))
        XCTAssertGreaterThan(wrapped.noteLines, 3)
        XCTAssertGreaterThan(measure("A longer sentence wrapping across the card", width: 90).height,
                             measure("A longer sentence wrapping across the card").height)
        let huge = measure(String(repeating: "line\n", count: 500))
        XCTAssertLessThanOrEqual(huge.height, 400)
        XCTAssertTrue(huge.notesTruncated)
    }

    func testCardsHaveIndependentRepeatableMotion() {
        let ids = (0..<20).map { UUID(uuidString: String(format: "12345678-1234-4567-89ab-%012d", $0))! }
        let profiles = ids.map(CardMotionProfile.init)
        XCTAssertEqual(profiles, ids.map(CardMotionProfile.init))
        XCTAssertEqual(Set(profiles.map(\.initialDelay)).count, 20)
        XCTAssertGreaterThan(Set(profiles.map(\.interval)).count, 15)
        XCTAssertGreaterThan(Set(profiles.map(\.amplitude)).count, 15)
        XCTAssertTrue(profiles.allSatisfy { abs($0.amplitude) < 3 && $0.interval >= 7 })
    }

    @MainActor
    func testViewportRendersBoundedNumberOfTasksAndCanReachEveryTask() {
        let line = Line()
        line.itemCount = 500
        line.visibleCount = 4
        for index in 0..<500 {
            line.ensureVisible(index: index)
            let range = line.renderedIndices(count: 500)
            XCTAssertTrue(range.contains(index))
            XCTAssertLessThanOrEqual(range.count, 6)
        }
        XCTAssertEqual(line.scroll, Layout.spacing * 496)
        line.scroll(by: -100_000_000)
        XCTAssertEqual(line.scroll, 0)
        XCTAssertEqual(line.renderedIndices(count: 0), 0..<0)
    }

    func testBlankClickPolicyPreservesControlsAndDragSessions() {
        let card = CGRect(x: 100, y: 70, width: 226, height: 100)
        XCTAssertFalse(VisibilityPolicy.shouldHideForClick(at: CGPoint(x: 150, y: 100), controls: [card], busy: false))
        XCTAssertTrue(VisibilityPolicy.shouldHideForClick(at: CGPoint(x: 400, y: 100), controls: [card], busy: false))
        XCTAssertTrue(VisibilityPolicy.shouldHideForClick(at: CGPoint(x: 150, y: 300), controls: [card], busy: false))
        XCTAssertFalse(VisibilityPolicy.shouldHideForClick(at: CGPoint(x: 400, y: 100), controls: [card], busy: true))
    }

    func testWindowTrackerDetectsSameAppWindowChangesAndOtherApps() {
        let first = ForegroundWindow(processID: 10, windowID: 1)
        var tracker = WindowSwitchTracker(baseline: first)
        XCTAssertFalse(tracker.changed(to: first))
        XCTAssertFalse(tracker.changed(to: nil))
        XCTAssertTrue(tracker.changed(to: ForegroundWindow(processID: 10, windowID: 2)))
        XCTAssertTrue(tracker.changed(to: ForegroundWindow(processID: 11, windowID: 3)))
    }

    @MainActor
    func testPreferencesDefaultToChineseAndPersistAllDisplayOptions() {
        let suite = "HangTodoSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.language, .chinese)
        preferences.language = .english
        preferences.cardSize = .large
        preferences.opensFromMenuBar = false
        preferences.showsOverFullScreen = true
        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.language, .english)
        XCTAssertEqual(restored.cardSize, .large)
        XCTAssertFalse(restored.opensFromMenuBar)
        XCTAssertTrue(restored.showsOverFullScreen)
        XCTAssertEqual(Localizer.text("工作", language: .english), "Work")
        XCTAssertEqual(Localizer.format("已完成 %d", language: .english, arguments: [12]), "Completed 12")
        XCTAssertEqual(Localizer.text("设置", language: .chinese), "设置")
    }

    @MainActor
    func testMenuContainsOnlySettingsAndQuit() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let delegate = AppDelegate(store: TaskStore(fileURL: folder.appendingPathComponent("tasks.json")))
        let menu = NSMenu()
        delegate.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.items.map(\.title), [L("设置…"), L("退出 HangTodo")])
    }

    func testSingleInstanceLockRejectsSecondOwnerAndReleasesOnExit() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("app.lock")
        var owner = try InstanceLock.acquire(at: url)
        XCTAssertNotNil(owner)
        XCTAssertNil(try InstanceLock.acquire(at: url))
        owner = nil
        let replacement = try InstanceLock.acquire(at: url)
        XCTAssertNotNil(replacement)
        withExtendedLifetime(replacement) { XCTAssertNil(try? InstanceLock.acquire(at: url)) }
    }
}
