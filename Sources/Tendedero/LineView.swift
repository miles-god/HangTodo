import SwiftUI

enum Layout {
    enum Size: String, CaseIterable {
        case small, medium, large
        var scale: CGFloat {
            switch self {
            case .small: return 0.9
            case .medium: return 1
            case .large: return 1.15
            }
        }
        var title: String {
            switch self {
            case .small: return L("小")
            case .medium: return L("中")
            case .large: return L("大")
            }
        }
    }

    static var size: Size {
        get { Size(rawValue: UserDefaults.standard.string(forKey: "lineSize") ?? "") ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lineSize") }
    }
    static var cardWidth: CGFloat { (226 * size.scale).rounded() }
    static var spacing: CGFloat { cardWidth + 24 }
    static let ropeTop: CGFloat = 65
    static let pinAbove: CGFloat = 9.5
    static let addID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    static let undoID = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    static let previousID = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
    static let nextID = UUID(uuidString: "00000000-0000-0000-0000-000000000008")!
    static let manageID = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
    static let emptyID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    static func sag(width: CGFloat) -> CGFloat { min(25, width * 0.018) }
    static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return ropeTop }
        let f = x / width
        return ropeTop + 4 * sag(width: width) * f * (1 - f)
    }
    static func x(index: Int, count: Int, width: CGFloat, visible: Int, scroll: CGFloat) -> CGFloat {
        let shown = min(count, visible)
        return width / 2 - CGFloat(max(0, shown - 1)) * spacing / 2 + CGFloat(index) * spacing - scroll
    }
}

extension Quadrant {
    var color: Color {
        switch self {
        case .importantUrgent: return Color(red: 0.78, green: 0.28, blue: 0.23)
        case .importantNotUrgent: return Color(red: 0.25, green: 0.43, blue: 0.72)
        case .notImportantUrgent: return Color(red: 0.66, green: 0.43, blue: 0.16)
        case .neither: return Color(red: 0.40, green: 0.48, blue: 0.43)
        }
    }
    var compactTitle: String {
        switch self {
        case .importantUrgent: return L("重要紧急")
        case .importantNotUrgent: return L("重要不急")
        case .notImportantUrgent: return L("紧急不重")
        case .neither: return L("其他")
        }
    }
}

struct LineView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var line: Line
    @ObservedObject private var preferences = AppPreferences.shared
    var onAdd: () -> Void
    var onEdit: (TodoTask) -> Void
    var onManageCategories: () -> Void
    var onDelete: (TodoTask) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let tasks = store.visibleTasks
            ZStack(alignment: .topLeading) {
                Rope(width: width)
                toolbar(compact: width < 1180 || preferences.language == .english)
                    .fixedSize()
                    .position(x: width / 2, y: 27)

                if tasks.isEmpty {
                    emptyState
                        .fixedSize()
                        .position(x: width / 2, y: 159)
                }
                ForEach(renderedTasks(tasks), id: \.element.id) { index, task in
                    let x = Layout.x(index: index, count: tasks.count, width: width,
                                     visible: line.visibleCount, scroll: line.scroll)
                    PeggedView(task: task, store: store, line: line, onEdit: { onEdit(task) }, onDelete: { onDelete(task) })
                        .position(x: x, y: Layout.ropeY(x: x, width: width) - Layout.pinAbove + ((line.cardMetrics[task.id]?.height ?? 100) + 14) / 2)
                        .opacity(min(1, max(0, min(x, width - x) / 65)))
                        .transition(.opacity.combined(with: .offset(y: -12)))
                }
                if tasks.count > line.visibleCount {
                    edgeButton(previous: true).position(x: 24, y: Layout.ropeTop + 68)
                    edgeButton(previous: false).position(x: width - 24, y: Layout.ropeTop + 68)
                }
                if line.categoryDockVisible {
                    categoryDock(width: width)
                        .position(x: width / 2, y: line.panelHeight - 26)
                } else if let undo = store.pendingUndo {
                    undoFooter(undo)
                        .fixedSize()
                        .position(x: width / 2, y: line.panelHeight - 21)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.85), value: tasks.map(\.id))
            .offset(y: line.revealed ? 0 : -(line.panelHeight + 12))
            .animation(reduceMotion ? nil : (line.revealed ? .spring(response: 0.42, dampingFraction: 0.86) : .easeIn(duration: 0.2)), value: line.revealed)
        }
        .environment(\.locale, preferences.language.locale)
        .onPreferenceChange(HitRectsKey.self) { line.hitRects = $0 }
        .onPreferenceChange(TargetRectsKey.self) {
            line.targetRects = $0.mapValues(\.rect)
            line.targetDestinations = $0.mapValues(\.destination)
        }
    }

    private func renderedTasks(_ tasks: [TodoTask]) -> [(offset: Int, element: TodoTask)] {
        var indices = Array(line.renderedIndices(count: tasks.count))
        if let dragging = line.draggingID, let index = tasks.firstIndex(where: { $0.id == dragging }), !indices.contains(index) {
            indices.append(index)
        }
        return indices.map { (offset: $0, element: tasks[$0]) }
    }

    private func edgeButton(previous: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                line.scroll(by: (previous ? -1 : 1) * Layout.spacing * CGFloat(line.visibleCount))
            }
        } label: {
            Image(systemName: previous ? "chevron.left" : "chevron.right")
                .font(.system(size: 14, weight: .semibold)).frame(width: 32, height: 58)
                .glassFrame(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .disabled(previous ? line.scroll <= 0 : line.scroll >= line.maxScroll)
        .opacity((previous ? line.scroll > 0 : line.scroll < line.maxScroll) ? 0.85 : 0.25)
        .accessibilityLabel(L(previous ? "上一组任务" : "下一组任务"))
        .reportHitRect(previous ? Layout.previousID : Layout.nextID)
    }

    private func toolbar(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Button { line.showsCategories.toggle() } label: {
                Label(store.selectedCategoryID.map(store.categoryName) ?? L("全部分类"), systemImage: "folder")
                    .lineLimit(1).frame(maxWidth: 120)
            }
            .help(L("选择任务分类"))
            .modifier(DockTarget(destination: store.selectedCategoryID.map(TaskDestination.category) ?? .pending, line: line))
            Divider().frame(height: 18)
            HStack(spacing: 3) {
                filterButton(L("全部"), quadrant: nil)
                ForEach(Quadrant.allCases) { quadrant in
                    filterButton(compact ? quadrant.compactTitle : quadrant.title, quadrant: quadrant)
                }
            }
            Divider().frame(height: 18)
            Button {
                store.showingCompleted.toggle()
            } label: {
                Label(F("已完成 %d", store.count(completed: true)), systemImage: store.showingCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundStyle(store.showingCompleted ? Color.accentColor : Color.primary)
            }
            .help(store.showingCompleted ? L("返回待办任务") : L("查看已完成任务，可以重新打开"))
            .padding(.vertical, 6)
            .modifier(DockTarget(destination: .completed, line: line))
            Button(action: onAdd) { Label(L("新增"), systemImage: "plus") }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel(L("新增任务"))
                .reportHitRect(Layout.addID)
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .glassFrame(cornerRadius: 14)
    }

    private func filterButton(_ title: String, quadrant: Quadrant?) -> some View {
        Button {
            store.selectedQuadrant = quadrant
            store.showingCompleted = false
        } label: {
            HStack(spacing: 5) {
                if let quadrant { Circle().fill(quadrant.color).frame(width: 5, height: 5) }
                Text(title)
                Text("\(store.count(in: quadrant))").foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(!store.showingCompleted && store.selectedQuadrant == quadrant ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .help(F("%@，拖入可以%@", quadrant?.title ?? L("全部待办"), quadrant == nil ? L("重新打开任务") : L("修改象限")))
        .accessibilityLabel(F("%@，%d 项待办", quadrant?.title ?? L("全部象限"), store.count(in: quadrant)))
        .accessibilityAddTraits(!store.showingCompleted && store.selectedQuadrant == quadrant ? [.isSelected] : [])
        .modifier(DockTarget(destination: quadrant.map(TaskDestination.quadrant) ?? .pending, line: line))
    }

    private func categoryDock(width: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                categoryButton(L("全部分类"), id: nil)
                ForEach(store.categories) { category in
                    categoryButton(store.categoryName(category.id), id: category.id)
                }
                Button(L("管理分类…"), action: onManageCategories)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .reportHitRect(Layout.manageID)
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
        }
        .frame(width: min(width - 80, CGFloat(store.categories.count + 2) * 145), height: 48)
        .font(.system(size: 12, weight: .medium)).buttonStyle(.plain)
        .glassFrame(cornerRadius: 14)
    }

    private func categoryButton(_ title: String, id: UUID?) -> some View {
        Button {
            store.selectedCategoryID = id
            line.showsCategories = false
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(title).lineLimit(1).frame(maxWidth: 120)
                Text("\(store.categoryCount(id))").monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(store.selectedCategoryID == id ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .help(id == nil ? L("显示全部分类") : L("拖入更改任务分类，保留完成状态"))
        .accessibilityLabel(F("分类%@，%d 项待办", title, store.categoryCount(id)))
        .modifier(DockTarget(destination: id.map(TaskDestination.category) ?? .pending, line: line))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.showingCompleted ? "checkmark.seal" : "note.text")
                .font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
            Text(store.showingCompleted ? L("这里还没有已完成的任务") : L("这根绳上暂时没有待办"))
                .font(.system(size: 13, weight: .medium))
            if store.showingCompleted {
                Button(L("返回待办")) { store.showingCompleted = false }.reportHitRect(Layout.emptyID)
            } else {
                Button(L("挂上一个新任务"), action: onAdd).reportHitRect(Layout.emptyID)
            }
        }
        .buttonStyle(.link)
        .padding(.horizontal, 30).padding(.vertical, 18)
        .glassFrame(cornerRadius: 16)
    }

    private func undoFooter(_ undo: CompletionUndo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
            Text(L(undo.message))
            Button(L("撤销")) { store.undoCompletion() }.buttonStyle(.link).reportHitRect(Layout.undoID)
        }
        .font(.system(size: 11)).buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .glassFrame(cornerRadius: 12)
    }
}

struct Rope: View {
    let width: CGFloat
    private var path: Path {
        Path { p in
            p.move(to: CGPoint(x: -20, y: Layout.ropeTop))
            p.addQuadCurve(to: CGPoint(x: width + 20, y: Layout.ropeTop),
                           control: CGPoint(x: width / 2, y: Layout.ropeTop + 2 * Layout.sag(width: width)))
        }
    }
    var body: some View {
        ZStack {
            path.stroke(Color.black.opacity(0.22), lineWidth: 1.4).offset(y: 1.2).blur(radius: 1.2)
            path.stroke(Color(white: 0.55), lineWidth: 1.2)
            path.stroke(Color.white.opacity(0.45), lineWidth: 0.4).offset(y: -0.35)
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                      .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .allowsHitTesting(false)
    }
}

struct HitRectsKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func reportHitRect(_ id: UUID) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: HitRectsKey.self, value: [id: g.frame(in: .global)])
        })
    }
}
