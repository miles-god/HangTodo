import AppKit
import Combine

@MainActor
final class Line: ObservableObject {
    @Published var revealed = false
    @Published var scroll: CGFloat = 0
    @Published var cardMetrics: [UUID: TaskCardMetrics] = [:]
    @Published var panelHeight: CGFloat = 250
    @Published var draggingID: UUID?
    @Published var dragDestination: TaskDestination?
    @Published var insertBefore = true
    @Published var showsCategories = false
    @Published var pointer: CGPoint?
    var hitRects: [UUID: CGRect] = [:]
    var targetRects: [UUID: CGRect] = [:]
    var targetDestinations: [UUID: TaskDestination] = [:]
    var visibleCount = 5
    var itemCount = 0

    var categoryDockVisible: Bool { draggingID != nil || showsCategories }

    func magnification(for destination: TaskDestination, targetID: UUID) -> CGFloat {
        if dragDestination == destination { return 1.15 }
        guard let pointer, let rect = targetRects[targetID] else { return 1 }
        let distance = hypot(pointer.x - rect.midX, (pointer.y - rect.midY) * 2)
        return 1 + 0.15 * max(0, 1 - distance / 70)
    }

    func endDragging() {
        draggingID = nil
        dragDestination = nil
        showsCategories = false
    }

    func scroll(by delta: CGFloat) {
        let next = min(maxScroll, max(0, scroll + delta))
        if scroll != next { scroll = next }
    }

    var maxScroll: CGFloat { CGFloat(max(0, itemCount - visibleCount)) * Layout.spacing }

    func ensureVisible(index: Int) {
        let first = Int(scroll / Layout.spacing)
        if index < first { scroll = CGFloat(index) * Layout.spacing }
        else if index >= first + visibleCount { scroll = CGFloat(index - visibleCount + 1) * Layout.spacing }
        scroll(by: 0)
    }

    func renderedIndices(count: Int) -> Range<Int> {
        let first = max(0, Int(scroll / Layout.spacing) - 1)
        let last = min(count, Int(ceil(scroll / Layout.spacing)) + visibleCount + 1)
        return min(first, last)..<last
    }
}
