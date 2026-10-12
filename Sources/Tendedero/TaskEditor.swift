import AppKit
import Combine
import SwiftUI

@MainActor
final class TaskEditor: NSObject, NSWindowDelegate {
    private var windows: [UUID: NSWindow] = [:]
    private let newTaskID = UUID()
    private var languageSubscription: AnyCancellable?

    override init() {
        super.init()
        languageSubscription = AppPreferences.shared.$language.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            for (id, window) in self.windows { window.title = L(id == self.newTaskID ? "挂上新任务" : "编辑任务") }
        }
    }

    func show(task: TodoTask?, store: TaskStore, onSaved: @escaping (TodoTask) -> Void) {
        let key = task?.id ?? newTaskID
        if let window = windows[key] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = task == nil ? L("挂上新任务") : L("编辑任务")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: TaskEditorView(task: task, store: store,
            onCancel: { [weak window] in window?.close() },
            onSaved: { [weak window] saved in window?.close(); onSaved(saved) }))
        windows[key] = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== window }
    }
}

private struct TaskEditorView: View {
    @ObservedObject private var preferences = AppPreferences.shared
    let task: TodoTask?
    @ObservedObject var store: TaskStore
    var onCancel: () -> Void
    var onSaved: (TodoTask) -> Void
    @State private var title: String
    @State private var notes: String
    @State private var categoryID: UUID
    @State private var quadrant: Quadrant
    @State private var validationMessage: String?
    @FocusState private var titleFocused: Bool

    init(task: TodoTask?, store: TaskStore, onCancel: @escaping () -> Void, onSaved: @escaping (TodoTask) -> Void) {
        self.task = task
        self.store = store
        self.onCancel = onCancel
        self.onSaved = onSaved
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _categoryID = State(initialValue: task?.categoryID ?? TaskCategory.workID)
        _quadrant = State(initialValue: task?.quadrant ?? .importantUrgent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(task == nil ? L("把下一件事挂上绳") : L("整理这项任务"))
                .font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 7) {
                Text(L("任务标题")).font(.system(size: 12, weight: .medium))
                TextField(L("要做什么？"), text: $title)
                    .textFieldStyle(.roundedBorder).focused($titleFocused)
                    .accessibilityLabel(L("任务标题"))
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("分类")).font(.system(size: 12, weight: .medium))
                    Picker(L("分类"), selection: $categoryID) {
                        ForEach(store.categories) { Text(store.categoryName($0.id)).tag($0.id) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("四象限")).font(.system(size: 12, weight: .medium))
                    Picker(L("四象限"), selection: $quadrant) {
                        ForEach(Quadrant.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(L("备注（可选）")).font(.system(size: 12, weight: .medium))
                TextEditor(text: $notes).font(.system(size: 13))
                    .padding(5).frame(height: 106)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.25)))
                    .accessibilityLabel(L("任务备注"))
            }
            if task?.isCompleted == true {
                Text(L("这项任务已完成，可在“已完成”视图中重新打开。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let validationMessage { Text(L(validationMessage)).font(.system(size: 12)).foregroundStyle(.red) }
            Spacer(minLength: 0)
            HStack {
                Text(L("保存在这台 Mac 上")).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(L("取消"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(task == nil ? L("挂上去") : L("保存"), action: save)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 460, height: 460)
        .environment(\.locale, preferences.language.locale)
        .onAppear { titleFocused = true }
        .onChange(of: store.categories.map(\.id)) { _, ids in
            if !ids.contains(categoryID) { categoryID = TaskCategory.workID }
        }
    }

    private func save() {
        if let task {
            guard store.updateTask(task.id, title: title, notes: notes, categoryID: categoryID, quadrant: quadrant),
                  let updated = store.tasks.first(where: { $0.id == task.id }) else {
                validationMessage = "无法保存，请检查任务是否仍然存在。"
                return
            }
            onSaved(updated)
        } else if store.addTask(title: title, notes: notes, categoryID: categoryID, quadrant: quadrant), let saved = store.tasks.last {
            onSaved(saved)
        }
    }
}
