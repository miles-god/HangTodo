import AppKit
import Combine
import SwiftUI

@MainActor
final class CategoryManager {
    private var window: NSWindow?
    private var languageSubscription: AnyCancellable?

    init() {
        languageSubscription = AppPreferences.shared.$language.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.window?.title = L("管理分类") }
    }

    func show(store: TaskStore) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("管理分类")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CategoryManagerView(store: store))
        self.window = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct CategoryManagerView: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @ObservedObject var store: TaskStore
    @State private var newName = ""
    @State private var deleting: TaskCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("给任务一个归属")).font(.system(size: 20, weight: .semibold))
            Text(L("工作是默认分类。删除其他分类时，任务会转入工作。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.categories) { category in
                        CategoryRow(category: category, store: store, onDelete: { deleting = category })
                    }
                }
            }
            Divider()
            HStack {
                TextField(L("新分类名称"), text: $newName).textFieldStyle(.roundedBorder)
                    .onSubmit(addCategory)
                Button(L("新增"), action: addCategory).disabled(!store.categoryNameIsAvailable(newName))
            }
            if !newName.isEmpty && !store.categoryNameIsAvailable(newName) {
                Text(L("分类名称不能为空或重复。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(24).frame(width: 460, height: 400)
        .environment(\.locale, preferences.language.locale)
        .alert(F("删除分类“%@”？", deleting?.name ?? ""), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(L("取消"), role: .cancel) { deleting = nil }
            Button(L("删除分类"), role: .destructive) {
                if let deleting { store.deleteCategory(deleting.id) }
                deleting = nil
            }
        } message: { Text(L("里面的待办和已完成任务都会转入“工作”，任务内容和状态将保留。")) }
    }

    private func addCategory() {
        if store.addCategory(newName) { newName = "" }
    }
}

private struct CategoryRow: View {
    @ObservedObject private var preferences = AppPreferences.shared
    let category: TaskCategory
    @ObservedObject var store: TaskStore
    var onDelete: () -> Void
    @State private var name: String

    init(category: TaskCategory, store: TaskStore, onDelete: @escaping () -> Void) {
        self.category = category
        self.store = store
        self.onDelete = onDelete
        _name = State(initialValue: category.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            if category.id == TaskCategory.workID {
                Text(L("工作"))
                Spacer()
                Text(L("默认分类")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                TextField(L("分类名称"), text: $name).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(F("重命名分类：%@", category.name))
                Button(L("保存")) { store.renameCategory(category.id, to: name) }
                    .disabled(name == category.name || !store.categoryNameIsAvailable(name, excluding: category.id))
                Button(action: onDelete) { Image(systemName: "trash") }
                    .accessibilityLabel(F("删除分类：%@", category.name))
            }
        }
        .padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}
