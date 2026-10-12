import SwiftUI

struct PeggedView: View {
    let task: TodoTask
    @ObservedObject var store: TaskStore
    @ObservedObject var line: Line
    @ObservedObject private var preferences = AppPreferences.shared
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var hovering = false
    @State private var swing: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tilt: Double { (Double(task.id.uuid.0 % 5) - 2) * 0.6 }
    private var metrics: TaskCardMetrics { line.cardMetrics[task.id] ?? .measure(task, width: Layout.cardWidth, scale: Layout.size.scale, maximumHeight: 500) }
    private var sways: Bool { line.revealed && !reduceMotion && line.draggingID == nil }

    var body: some View {
        VStack(spacing: -12) {
            Clothespin(color: task.quadrant.color).zIndex(1)
            card
        }
        .frame(width: Layout.cardWidth, height: metrics.height + 14)
        .rotationEffect(.degrees(reduceMotion ? 0 : tilt + swing), anchor: .top)
        .task(id: sways) {
            guard sways else { swing = 0; return }
            let motion = CardMotionProfile(id: task.id)
            do {
                try await Task.sleep(for: .seconds(motion.initialDelay))
                while !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.25)) { swing = motion.amplitude }
                    try await Task.sleep(for: .seconds(0.25))
                    withAnimation(.interpolatingSpring(stiffness: motion.stiffness, damping: motion.damping)) { swing = 0 }
                    try await Task.sleep(for: .seconds(motion.interval))
                }
            } catch { swing = 0 }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    store.setCompleted(task.id, !task.isCompleted)
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(task.isCompleted ? Color.secondary : task.quadrant.color)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(F("%@：%@", L(task.isCompleted ? "重新打开" : "完成"), task.title))
                .help(task.isCompleted ? L("重新打开，回到原分类和象限") : L("标记完成，随后可以撤销"))
                Text(task.title)
                    .font(.system(size: 14 * Layout.size.scale, weight: .medium))
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted, color: .secondary.opacity(0.5))
                    .lineLimit(3).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                    .help(task.quadrant.title)
                Menu {
                    Button(L("编辑…"), action: onEdit)
                    Button(task.isCompleted ? L("重新打开") : L("标记完成")) { store.setCompleted(task.id, !task.isCompleted) }
                    Menu(L("修改象限")) {
                        ForEach(Quadrant.allCases) { quadrant in
                            Button(quadrant.title) { change(quadrant: quadrant) }
                        }
                    }
                    Menu(L("移动到分类")) {
                        ForEach(store.categories) { category in
                            Button(store.categoryName(category.id)) { change(categoryID: category.id) }
                        }
                    }
                    Divider()
                    Button(L("删除任务…"), role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                }
                .menuIndicator(.hidden)
                .accessibilityLabel(F("任务操作：%@", task.title))
            }
            if metrics.noteLines > 0 {
                Text(task.notes.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 11 * Layout.size.scale)).foregroundStyle(.secondary)
                    .lineLimit(metrics.noteLines)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(metrics.notesTruncated ? L("点击查看完整备注") : task.notes)
                HStack(spacing: 6) {
                    Label(store.categoryName(task.categoryID), systemImage: "folder")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let completed = task.completedAt {
                        Text(completed, format: .dateTime.month().day()).lineLimit(1)
                    }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(width: Layout.cardWidth, height: metrics.height, alignment: .top)
        .glassFrame(cornerRadius: 15)
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1.5).fill(task.quadrant.color.opacity(0.7))
                .frame(width: 42, height: 2).padding(.top, 1)
        }
        .shadow(color: .black.opacity(hovering ? 0.22 : 0.15), radius: hovering ? 12 : 8, y: 5)
        .scaleEffect(hovering && !reduceMotion ? 1.015 : 1, anchor: .top)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .overlay(TaskDragArea(task: task, line: line, onEdit: onEdit))
        .opacity(line.draggingID == task.id ? 0.4 : 1)
        .overlay(alignment: line.insertBefore ? .leading : .trailing) {
            if line.dragDestination == .task(task.id) {
                Capsule().fill(Color.accentColor).frame(width: 3, height: metrics.height - 18)
                    .offset(x: line.insertBefore ? -10 : 10)
            }
        }
        .reportHitRect(task.id)
    }

    private func change(categoryID: UUID? = nil, quadrant: Quadrant? = nil) {
        store.updateTask(task.id, title: task.title, notes: task.notes,
                         categoryID: categoryID ?? task.categoryID, quadrant: quadrant ?? task.quadrant)
    }

}

extension View {
    func glassFrame(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(.regularMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.5), lineWidth: 0.75))
            .overlay(shape.stroke(Color.black.opacity(0.10), lineWidth: 0.5).padding(-0.5))
    }
}

struct Clothespin: View {
    var color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.70), Color(white: 0.93), Color(white: 0.65)], startPoint: .leading, endPoint: .trailing))
            .frame(width: 9, height: 26)
            .overlay(alignment: .bottom) { Capsule().fill(color).frame(width: 5, height: 6).padding(.bottom, 3) }
            .overlay(alignment: .top) { Capsule().fill(.black.opacity(0.32)).frame(width: 5, height: 1.4).padding(.top, 8.5) }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1.5)
            .allowsHitTesting(false)
    }
}
