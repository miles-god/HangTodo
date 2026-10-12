import AppKit
import SwiftUI
import XCTest
@testable import HangTodo

final class NativeDropTests: XCTestCase {
    @MainActor
    func testSwiftUITargetGeometryRoutesToNativeReceiver() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "HangTodoNativeGeometryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = TaskStore(fileURL: folder.appendingPathComponent("tasks.json"), defaults: defaults)
        store.addTask(title: "跨象限移动")
        let line = Line()
        line.revealed = true
        let root = LineView(store: store, line: line, onAdd: {}, onEdit: { _ in }, onManageCategories: {}, onDelete: { _ in })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: 1200, height: 300)
        let view = TaskDropView(content: host, store: store, line: line)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        let deadline = Date().addingTimeInterval(2)
        while line.targetDestinations.isEmpty && Date() < deadline {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        let targetID = try XCTUnwrap(line.targetDestinations.first(where: { $0.value == .quadrant(.importantNotUrgent) })?.key)
        let rect = try XCTUnwrap(line.targetRects[targetID])
        let source = try XCTUnwrap(findSource(in: host))
        line.draggingID = source.taskID
        let info = TestDraggingInfo(source: source, at: CGPoint(x: rect.midX, y: rect.midY), in: view)
        defer { info.draggingPasteboard.releaseGlobally() }
        var hit = view.hitTest(info.draggingLocation)
        while let current = hit, info.draggingPasteboard.availableType(from: current.registeredDraggedTypes) == nil {
            hit = current.superview
        }
        XCTAssertTrue(hit === view, "The native receiver must be the first matching drag destination")
        XCTAssertEqual(view.draggingEntered(info), NSDragOperation.move)
        XCTAssertTrue(view.prepareForDragOperation(info))
        XCTAssertTrue(view.performDragOperation(info))
        XCTAssertEqual(store.tasks[0].quadrant, .importantNotUrgent)
    }

    @MainActor
    private func findSource(in view: NSView) -> TaskDragView? {
        if let source = view as? TaskDragView { return source }
        return view.subviews.lazy.compactMap { self.findSource(in: $0) }.first
    }

    @MainActor
    func testNativePasteboardDropMovesToQuadrantCategoryAndCompleted() throws {
        try withReceiver { store, line, view, source in
            store.addCategory("生活")
            let lifeID = store.categories.last!.id
            let target = UUID()
            line.targetRects[target] = CGRect(x: 100, y: 10, width: 120, height: 32)
            line.targetDestinations[target] = .quadrant(.importantNotUrgent)
            let info = TestDraggingInfo(source: source, at: CGPoint(x: 160, y: 26), in: view)
            defer { info.draggingPasteboard.releaseGlobally() }
            XCTAssertEqual(info.draggingLocation.y, 274, accuracy: 0.001)
            XCTAssertTrue(view.registeredDraggedTypes.contains(TaskDragView.type))
            XCTAssertEqual(view.draggingEntered(info), .move)
            XCTAssertEqual(line.dragDestination, .quadrant(.importantNotUrgent))
            XCTAssertTrue(view.prepareForDragOperation(info))
            XCTAssertTrue(view.performDragOperation(info))
            XCTAssertEqual(store.count(in: .importantUrgent), 0)
            XCTAssertEqual(store.count(in: .importantNotUrgent), 1)
            XCTAssertEqual(store.tasks[0].notes, "原备注")
            XCTAssertEqual(store.tasks[0].categoryID, TaskCategory.workID)
            let restored = TaskStore(fileURL: store.fileURL)
            XCTAssertEqual(restored.tasks[0].quadrant, .importantNotUrgent)

            line.targetDestinations[target] = .category(lifeID)
            XCTAssertEqual(view.draggingUpdated(info), .move)
            XCTAssertTrue(view.performDragOperation(info))
            XCTAssertEqual(store.tasks[0].categoryID, lifeID)
            XCTAssertEqual(store.categoryCount(lifeID), 1)

            line.targetDestinations[target] = .completed
            XCTAssertEqual(view.draggingUpdated(info), .move)
            XCTAssertTrue(view.performDragOperation(info))
            XCTAssertTrue(store.tasks[0].isCompleted)
            line.targetDestinations[target] = .pending
            XCTAssertTrue(view.performDragOperation(info))
            XCTAssertFalse(store.tasks[0].isCompleted)
            XCTAssertEqual(store.tasks[0].quadrant, .importantNotUrgent)
            XCTAssertEqual(store.tasks[0].categoryID, lifeID)
        }
    }

    @MainActor
    func testNativeReceiverReordersByActualCardHalfAndClearsExitedHighlight() throws {
        try withReceiver { store, line, view, source in
            store.addTask(title: "目标任务")
            let targetID = store.tasks[1].id
            line.hitRects[targetID] = CGRect(x: 250, y: 80, width: 226, height: 100)
            let info = TestDraggingInfo(source: source, at: CGPoint(x: 440, y: 110), in: view)
            defer { info.draggingPasteboard.releaseGlobally() }
            XCTAssertEqual(view.draggingEntered(info), .move)
            XCTAssertEqual(line.dragDestination, .task(targetID))
            XCTAssertFalse(line.insertBefore)
            XCTAssertTrue(view.performDragOperation(info))
            XCTAssertEqual(store.tasks.map(\.title), ["目标任务", "原任务"])
            info.draggingLocation = view.convert(CGPoint(x: 280, y: 110), to: nil)
            XCTAssertEqual(view.draggingUpdated(info), .move)
            XCTAssertTrue(line.insertBefore)
            XCTAssertTrue(view.performDragOperation(info))
            XCTAssertEqual(store.tasks.map(\.title), ["原任务", "目标任务"])
            _ = view.draggingUpdated(info)
            view.draggingExited(info)
            XCTAssertNil(line.dragDestination)
            XCTAssertEqual(line.draggingID, source.taskID)
        }
    }

    @MainActor
    func testNativeReceiverRejectsMismatchedIDsUnsupportedOperationsAndBlankDrops() throws {
        try withReceiver { store, line, view, source in
            let target = UUID()
            line.targetRects[target] = CGRect(x: 100, y: 10, width: 120, height: 32)
            line.targetDestinations[target] = .quadrant(.neither)
            let info = TestDraggingInfo(source: source, at: CGPoint(x: 160, y: 26), in: view)
            defer { info.draggingPasteboard.releaseGlobally() }
            info.draggingSourceOperationMask = .copy
            XCTAssertEqual(view.draggingEntered(info), [])
            XCTAssertFalse(view.performDragOperation(info))
            info.draggingSourceOperationMask = .move
            info.draggingPasteboard.setString(UUID().uuidString, forType: TaskDragView.type)
            XCTAssertFalse(view.prepareForDragOperation(info))
            XCTAssertFalse(view.performDragOperation(info))
            info.draggingPasteboard.setString(source.taskID.uuidString, forType: TaskDragView.type)
            info.draggingLocation = view.convert(CGPoint(x: 500, y: 240), to: nil)
            XCTAssertEqual(view.draggingUpdated(info), [])
            XCTAssertFalse(view.performDragOperation(info))
            info.draggingLocation = view.convert(CGPoint(x: 160, y: 26), to: nil)
            line.draggingID = nil
            XCTAssertFalse(view.performDragOperation(info))
            XCTAssertEqual(store.tasks[0].quadrant, .importantUrgent)
            XCTAssertEqual(store.tasks.count, 1)
        }
    }

    @MainActor
    private func withReceiver(_ check: (TaskStore, Line, TaskDropView, TaskDragView) throws -> Void) throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "HangTodoNativeDropTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = TaskStore(fileURL: folder.appendingPathComponent("tasks.json"), defaults: defaults)
        store.addTask(title: "原任务", notes: "原备注")
        let line = Line()
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 300))
        let view = TaskDropView(content: content, store: store, line: line)
        let window = NSWindow(contentRect: content.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        let source = TaskDragView()
        source.taskID = store.tasks[0].id
        source.line = line
        line.draggingID = source.taskID
        try withExtendedLifetime(window) { try check(store, line, view, source) }
    }
}

@MainActor
private final class TestDraggingInfo: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .move
    var draggingLocation: NSPoint
    let draggingPasteboard = NSPasteboard.withUniqueName()
    let draggingSource: Any?
    var draggingSequenceNumber: Int { 1 }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(source: TaskDragView, at point: CGPoint, in view: TaskDropView) {
        draggingSource = source
        draggingDestinationWindow = view.window
        draggingLocation = view.convert(point, to: nil)
        super.init()
        let item = NSPasteboardItem()
        item.setString(source.taskID.uuidString, forType: TaskDragView.type)
        draggingPasteboard.writeObjects([item])
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
