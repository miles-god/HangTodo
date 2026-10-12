import XCTest
import AppKit
@testable import HangTodo

final class TaskStoreTests: XCTestCase {
    @MainActor
    func testDragAreaLeavesCheckboxAndMenuClickable() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 226, height: 150))
        let view = TaskDragView(frame: container.bounds)
        container.addSubview(view)
        let checkbox = view.convert(NSPoint(x: 24, y: 24), to: container)
        let menu = view.convert(NSPoint(x: 200, y: 24), to: container)
        let body = view.convert(NSPoint(x: 100, y: 100), to: container)
        XCTAssertNil(view.hitTest(checkbox))
        XCTAssertNil(view.hitTest(menu))
        XCTAssertTrue(view.hitTest(body) === view)
        var edited = false
        view.onEdit = { edited = true }
        XCTAssertTrue(view.accessibilityPerformPress())
        XCTAssertTrue(edited)
    }

    @MainActor
    func testDockProximityAndCancelledDragReset() {
        let line = Line()
        let targetID = UUID()
        line.targetRects[targetID] = CGRect(x: 100, y: 0, width: 80, height: 32)
        XCTAssertEqual(line.magnification(for: .pending, targetID: targetID), 1)
        line.pointer = CGPoint(x: 140, y: 16)
        XCTAssertEqual(line.magnification(for: .pending, targetID: targetID), 1.15, accuracy: 0.001)
        line.pointer = CGPoint(x: 170, y: 16)
        XCTAssertGreaterThan(line.magnification(for: .pending, targetID: targetID), 1)
        XCTAssertLessThan(line.magnification(for: .pending, targetID: targetID), 1.15)
        line.pointer = CGPoint(x: 230, y: 16)
        XCTAssertEqual(line.magnification(for: .pending, targetID: targetID), 1)
        line.draggingID = UUID()
        line.dragDestination = .completed
        line.showsCategories = true
        line.endDragging()
        XCTAssertNil(line.draggingID)
        XCTAssertNil(line.dragDestination)
        XCTAssertFalse(line.categoryDockVisible)
    }

    @MainActor
    func testPendingBadgesUpdateWhileCompletedViewRemainsOpen() throws {
        try withStore { store, _, _ in
            store.addTask(title: "需要恢复", quadrant: .importantUrgent)
            let id = store.tasks[0].id
            store.setCompleted(id, true)
            store.selectedQuadrant = .neither
            store.showingCompleted = true
            XCTAssertEqual(store.visibleTasks.map(\.id), [id])
            XCTAssertEqual(store.count(in: .importantUrgent), 0)
            XCTAssertEqual(store.count(completed: true), 1)
            XCTAssertTrue(store.setCompleted(id, false))
            XCTAssertTrue(store.showingCompleted)
            XCTAssertEqual(store.count(in: .importantUrgent), 1)
            XCTAssertEqual(store.categoryCount(TaskCategory.workID), 1)
            XCTAssertEqual(store.count(completed: true), 0)
            XCTAssertTrue(store.visibleTasks.isEmpty)
            XCTAssertTrue(store.undoCompletion())
            XCTAssertEqual(store.count(in: .importantUrgent), 0)
            XCTAssertEqual(store.count(completed: true), 1)
        }
    }

    @MainActor
    func testManualOrderPersistsAcrossRestartAndCompletion() throws {
        try withStore { store, _, defaults in
            for title in ["一", "二", "三"] { store.addTask(title: title) }
            let first = store.tasks[0], third = store.tasks[2]
            XCTAssertTrue(store.dropTask(third.id, at: .task(first.id)))
            XCTAssertEqual(store.visibleTasks.map(\.title), ["三", "一", "二"])
            let restored = TaskStore(fileURL: store.fileURL, defaults: defaults)
            XCTAssertEqual(restored.visibleTasks.map(\.title), ["三", "一", "二"])
            restored.setCompleted(third.id, true)
            restored.setCompleted(third.id, false)
            XCTAssertEqual(restored.visibleTasks.map(\.title), ["三", "一", "二"])
            XCTAssertTrue(restored.dropTask(third.id, at: .task(first.id), before: false))
            XCTAssertEqual(restored.visibleTasks.map(\.title), ["一", "三", "二"])
            XCTAssertEqual(restored.tasks.first(where: { $0.id == third.id })?.createdAt, third.createdAt)
        }
    }

    @MainActor
    func testDropsChangeOnlyIntendedAttributesAndAppendToDestination() throws {
        try withStore { store, _, _ in
            store.addCategory("生活")
            let life = store.categories.last!.id
            store.addTask(title: "已有任务", categoryID: life, quadrant: .importantNotUrgent)
            store.addTask(title: "移动任务", notes: "保留备注")
            let id = store.tasks.last!.id
            XCTAssertTrue(store.dropTask(id, at: .quadrant(.importantNotUrgent)))
            XCTAssertTrue(store.dropTask(id, at: .category(life)))
            store.selectedCategoryID = life
            XCTAssertEqual(store.visibleTasks.map(\.title), ["已有任务", "移动任务"])
            XCTAssertEqual(store.tasks.first(where: { $0.id == id })?.notes, "保留备注")
            XCTAssertTrue(store.dropTask(id, at: .completed))
            XCTAssertEqual(store.count(completed: true), 1)
            XCTAssertTrue(store.dropTask(id, at: .category(TaskCategory.workID)))
            XCTAssertTrue(store.tasks.first(where: { $0.id == id })!.isCompleted)
            XCTAssertTrue(store.dropTask(id, at: .quadrant(.importantUrgent)))
            let task = store.tasks.first(where: { $0.id == id })!
            XCTAssertFalse(task.isCompleted)
            XCTAssertEqual(task.categoryID, TaskCategory.workID)
            XCTAssertEqual(task.quadrant, .importantUrgent)
            XCTAssertEqual(store.tasks.count, 2)
        }
    }

    @MainActor
    func testInvalidOrUnsavedDropCannotLoseOrReorderTasks() throws {
        try withStore { store, folder, _ in
            store.addTask(title: "一")
            store.addTask(title: "二")
            store.addTask(title: "其他象限", quadrant: .neither)
            let first = store.tasks[0].id, second = store.tasks[1].id, other = store.tasks[2].id
            XCTAssertFalse(store.dropTask(first, at: .task(first)))
            XCTAssertFalse(store.dropTask(first, at: .task(other)))
            XCTAssertFalse(store.dropTask(first, at: .category(UUID())))
            XCTAssertFalse(store.dropTask(UUID(), at: .completed))
            let original = store.tasks
            try FileManager.default.removeItem(at: folder)
            try Data("blocked".utf8).write(to: folder)
            XCTAssertFalse(store.dropTask(second, at: .task(first)))
            XCTAssertEqual(store.tasks, original)
            XCTAssertFalse(store.dropTask(first, at: .quadrant(.neither)))
            XCTAssertEqual(store.tasks, original)
        }
    }

    @MainActor
    func testLongLineClampsAndBringsRestoredTaskIntoView() {
        let line = Line()
        line.visibleCount = 4
        line.itemCount = 15
        line.scroll(by: Layout.spacing * 4)
        XCTAssertEqual(line.scroll, Layout.spacing * 4)
        line.scroll(by: 100_000)
        XCTAssertEqual(line.scroll, Layout.spacing * 11)
        line.ensureVisible(index: 6)
        XCTAssertEqual(line.scroll, Layout.spacing * 6)
        line.ensureVisible(index: 14)
        XCTAssertEqual(line.scroll, Layout.spacing * 11)
        line.itemCount = 2
        line.scroll(by: 0)
        XCTAssertEqual(line.scroll, 0)
        line.scroll(by: -100_000)
        XCTAssertEqual(line.scroll, 0)
    }

    @MainActor
    private func withStore(_ test: (TaskStore, URL, UserDefaults) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "HangTodoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        try test(TaskStore(fileURL: folder.appendingPathComponent("tasks.json"), defaults: defaults), folder, defaults)
    }

    @MainActor
    func testDefaultsValidationAndNoCapacityEviction() throws {
        try withStore { store, _, _ in
            XCTAssertEqual(store.selectedCategoryID, TaskCategory.workID)
            XCTAssertFalse(store.addTask(title: " \n "))
            for i in 0..<30 { XCTAssertTrue(store.addTask(title: "任务 \(i)")) }
            XCTAssertEqual(store.tasks.count, 30)
            XCTAssertTrue(store.tasks.allSatisfy { $0.categoryID == TaskCategory.workID && $0.quadrant == .importantUrgent })
        }
    }

    @MainActor
    func testCompleteReloadReopenKeepsIdentityContentAndPosition() throws {
        try withStore { store, _, defaults in
            XCTAssertTrue(store.addCategory("生活"))
            let category = store.categories.last!.id
            XCTAssertTrue(store.addTask(title: "买东西", notes: "清单", categoryID: category, quadrant: .importantNotUrgent))
            XCTAssertTrue(store.addTask(title: "第二件事", categoryID: category, quadrant: .importantNotUrgent))
            let task = store.tasks[0]
            XCTAssertTrue(store.setCompleted(task.id, true))
            let restored = TaskStore(fileURL: store.fileURL, defaults: defaults)
            restored.selectedCategoryID = category
            restored.showingCompleted = true
            XCTAssertEqual(restored.visibleTasks.map(\.id), [task.id])
            XCTAssertTrue(restored.setCompleted(task.id, false))
            restored.showingCompleted = false
            XCTAssertEqual(restored.tasks[0], task)
            XCTAssertEqual(restored.visibleTasks.first?.id, task.id)
        }
    }

    @MainActor
    func testUndoTargetsLatestActionAndSurvivesFailedWrite() throws {
        try withStore { store, folder, _ in
            store.addTask(title: "一")
            store.addTask(title: "二")
            let first = store.tasks[0].id, second = store.tasks[1].id
            store.setCompleted(first, true)
            store.setCompleted(second, true)
            XCTAssertTrue(store.undoCompletion())
            XCTAssertTrue(store.tasks[0].isCompleted)
            XCTAssertFalse(store.tasks[1].isCompleted)
            XCTAssertTrue(store.setCompleted(first, false))
            try FileManager.default.removeItem(at: folder)
            try Data("blocked".utf8).write(to: folder)
            XCTAssertFalse(store.undoCompletion())
            XCTAssertFalse(store.tasks[0].isCompleted)
            XCTAssertNotNil(store.pendingUndo)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    @MainActor
    func testCategoryDeletionPreservesPendingAndCompletedTasks() throws {
        try withStore { store, _, _ in
            XCTAssertFalse(store.addCategory(" 工作 "))
            XCTAssertTrue(store.addCategory("生活"))
            let category = store.categories.last!.id
            XCTAssertTrue(store.renameCategory(category, to: "家里"))
            store.addTask(title: "待办", categoryID: category)
            store.addTask(title: "已完成", categoryID: category)
            store.setCompleted(store.tasks[1].id, true)
            store.selectedCategoryID = category
            XCTAssertTrue(store.deleteCategory(category))
            XCTAssertEqual(store.tasks.count, 2)
            XCTAssertTrue(store.tasks.allSatisfy { $0.categoryID == TaskCategory.workID })
            XCTAssertTrue(store.tasks[1].isCompleted)
            XCTAssertEqual(store.selectedCategoryID, TaskCategory.workID)
            XCTAssertFalse(store.deleteCategory(TaskCategory.workID))
            XCTAssertFalse(store.renameCategory(TaskCategory.workID, to: "别的"))
        }
    }

    @MainActor
    func testFiltersAndPreferencesRemainIndependentOfCompletion() throws {
        try withStore { store, _, defaults in
            store.addTask(title: "重要", quadrant: .importantUrgent)
            store.addTask(title: "稍后", quadrant: .neither)
            store.selectedCategoryID = nil
            store.selectedQuadrant = .neither
            let task = store.visibleTasks[0]
            store.setCompleted(task.id, true)
            XCTAssertTrue(store.visibleTasks.isEmpty)
            XCTAssertEqual(store.count(in: .neither, completed: true), 1)
            store.showingCompleted = true
            XCTAssertEqual(store.visibleTasks.map(\.id), [task.id])
            let restored = TaskStore(fileURL: store.fileURL, defaults: defaults)
            XCTAssertNil(restored.selectedCategoryID)
            XCTAssertEqual(restored.selectedQuadrant, .neither)
            XCTAssertFalse(restored.showingCompleted)
        }
    }

    @MainActor
    func testCorruptArchiveIsNeverOverwritten() throws {
        try withStore { store, folder, defaults in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let original = Data("not json".utf8)
            try original.write(to: store.fileURL)
            let restored = TaskStore(fileURL: store.fileURL, defaults: defaults)
            XCTAssertNotNil(restored.errorMessage)
            XCTAssertFalse(restored.addTask(title: "不能覆盖"))
            XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
            XCTAssertTrue(restored.tasks.isEmpty)
        }
    }
}
