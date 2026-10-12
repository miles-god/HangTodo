import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskDragArea: NSViewRepresentable {
    let task: TodoTask
    let line: Line
    var onEdit: () -> Void

    func makeNSView(context: Context) -> TaskDragView {
        let view = TaskDragView()
        configure(view)
        return view
    }

    func updateNSView(_ view: TaskDragView, context: Context) { configure(view) }

    private func configure(_ view: TaskDragView) {
        view.taskID = task.id
        view.previewTitle = task.title
        view.line = line
        view.onEdit = onEdit
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(F("编辑任务：%@", task.title))
        view.setAccessibilityHelp(L("点击编辑，拖动排序或移动到象限、分类和已完成。"))
    }
}

final class TaskDragView: NSView, NSDraggingSource {
    static let type = NSPasteboard.PasteboardType(UTType(exportedAs: "app.hangtodo.task").identifier)
    var taskID = UUID()
    var previewTitle = ""
    weak var line: Line?
    var onEdit: () -> Void = {}
    private var downPoint: NSPoint?
    private var startedDrag = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { onEdit(); return true }

    // Leave the checkbox and action menu to SwiftUI, so dragging never completes a task.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let checkbox = NSRect(x: 10, y: 10, width: 34, height: 34)
        let menu = NSRect(x: bounds.width - 42, y: 10, width: 32, height: 34)
        if checkbox.contains(local) || menu.contains(local) { return nil }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        addCursorRect(NSRect(x: 44, y: 0, width: max(0, bounds.width - 88), height: min(44, bounds.height)), cursor: .openHand)
        addCursorRect(NSRect(x: 0, y: 44, width: bounds.width, height: max(0, bounds.height - 44)), cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        startedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, !startedDrag, let line, let host = window?.contentView else { return }
        guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
        let item = NSPasteboardItem()
        item.setString(taskID.uuidString, forType: Self.type)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let rect = convert(bounds, to: host)
        let image: NSImage
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: rect) {
            host.cacheDisplay(in: rect, to: bitmap)
            image = NSImage(size: bounds.size)
            image.addRepresentation(bitmap)
        } else {
            let title = previewTitle
            image = NSImage(size: bounds.size, flipped: true) { frame in
                NSColor.windowBackgroundColor.setFill()
                NSBezierPath(roundedRect: frame, xRadius: 15, yRadius: 15).fill()
                (title as NSString).draw(in: frame.insetBy(dx: 14, dy: 14), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor])
                return true
            }
        }
        dragging.setDraggingFrame(bounds, contents: image)
        startedDrag = true
        line.draggingID = taskID
        let session = beginDraggingSession(with: [dragging], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        if downPoint != nil && !startedDrag { onEdit() }
        downPoint = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        downPoint = nil
        startedDrag = false
        line?.endDragging()
    }
}

// A native receiver matches the native drag source; SwiftUI supplies target geometry only.
final class TaskDropView: NSView {
    private let store: TaskStore
    private let line: Line

    init(content: NSView, store: TaskStore, line: Line) {
        self.store = store
        self.line = line
        super.init(frame: content.frame)
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        registerForDraggedTypes([TaskDragView.type])
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { line.dragDestination = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { context(for: sender) != nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let drop = context(for: sender) else { return false }
        let saved = store.dropTask(drop.id, at: drop.destination, before: drop.before)
        line.dragDestination = nil
        return saved
    }

    private func updateDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        let drop = context(for: sender)
        line.dragDestination = drop?.destination
        if let drop {
            line.insertBefore = drop.before
            let point = convert(sender.draggingLocation, from: nil)
            if line.pointer != point { line.pointer = point }
            return .move
        }
        return []
    }

    private func context(for sender: NSDraggingInfo) -> (id: UUID, destination: TaskDestination, before: Bool)? {
        guard sender.draggingSourceOperationMask.contains(.move),
              let rawID = sender.draggingPasteboard.string(forType: TaskDragView.type), let id = UUID(uuidString: rawID),
              let source = sender.draggingSource as? TaskDragView, source.line === line, source.taskID == id,
              line.draggingID == id else { return nil }
        let point = convert(sender.draggingLocation, from: nil)
        guard bounds.contains(point) else { return nil }
        let targets = line.targetRects.filter { $0.value.insetBy(dx: -5, dy: -5).contains(point) }
        if let target = targets.min(by: { distance(point, to: $0.value) < distance(point, to: $1.value) }),
           let destination = line.targetDestinations[target.key], store.canDrop(id, at: destination) {
            return (id, destination, true)
        }
        if let card = line.hitRects.filter({ $0.value.contains(point) && store.canDrop(id, at: .task($0.key)) })
            .min(by: { distance(point, to: $0.value) < distance(point, to: $1.value) }) {
            return (id, .task(card.key), point.x < card.value.midX)
        }
        return nil
    }

    private func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(point.x - rect.midX, point.y - rect.midY)
    }
}

struct DropTargetRegion: Equatable {
    let destination: TaskDestination
    let rect: CGRect
}

struct TargetRectsKey: PreferenceKey {
    static var defaultValue: [UUID: DropTargetRegion] = [:]
    static func reduce(value: inout [UUID: DropTargetRegion], nextValue: () -> [UUID: DropTargetRegion]) {
        value.merge(nextValue()) { $1 }
    }
}

struct DockTarget: ViewModifier {
    let destination: TaskDestination
    @ObservedObject var line: Line
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var targetID = UUID()

    func body(content: Content) -> some View {
        content
            .reportHitRect(targetID)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: TargetRectsKey.self,
                    value: [targetID: DropTargetRegion(destination: destination, rect: geometry.frame(in: .global))])
            })
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(line.dragDestination == destination ? 0.7 : 0), lineWidth: 1.5))
            .scaleEffect(reduceMotion ? 1 : line.magnification(for: destination, targetID: targetID))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: line.magnification(for: destination, targetID: targetID))
    }
}
