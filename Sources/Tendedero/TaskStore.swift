import Combine
import Foundation

enum Quadrant: String, Codable, CaseIterable, Identifiable {
    case importantUrgent, importantNotUrgent, notImportantUrgent, neither

    var id: String { rawValue }
    var title: String {
        switch self {
        case .importantUrgent: return L("重要且紧急")
        case .importantNotUrgent: return L("重要不紧急")
        case .notImportantUrgent: return L("紧急不重要")
        case .neither: return L("不重要不紧急")
        }
    }
    var rank: Int { Self.allCases.firstIndex(of: self)! }
}

struct TaskCategory: Codable, Identifiable, Equatable {
    static let workID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let work = TaskCategory(id: workID, name: "工作")
    let id: UUID
    var name: String
}

struct TodoTask: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var notes: String
    var categoryID: UUID
    var quadrant: Quadrant
    let createdAt: Date
    var completedAt: Date?

    var isCompleted: Bool { completedAt != nil }
}

enum TaskDestination: Hashable {
    case task(UUID)
    case quadrant(Quadrant)
    case category(UUID)
    case pending
    case completed
}

private struct TaskArchive: Codable {
    var version = 1
    var categories: [TaskCategory] = [.work]
    var tasks: [TodoTask] = []

    func validate() throws {
        guard version == 1,
              categories.contains(.work),
              Set(categories.map(\.id)).count == categories.count,
              Set(tasks.map(\.id)).count == tasks.count,
              categories.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              tasks.allSatisfy({ task in
                  !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && categories.contains(where: { $0.id == task.categoryID })
              }) else { throw StoreError.invalidArchive }
    }
}

private enum StoreError: LocalizedError {
    case invalidArchive
    var errorDescription: String? { L("任务文件格式不正确或版本不受支持。原文件已保留，请检查文件后重新启动。") }
}

struct CompletionUndo: Identifiable {
    let id = UUID()
    let taskID: UUID
    let previousDate: Date?
    let expectedDate: Date?
    let message: String
}

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TodoTask] = []
    @Published private(set) var categories: [TaskCategory] = [.work]
    @Published private(set) var pendingUndo: CompletionUndo?
    @Published var errorMessage: String?
    @Published var selectedCategoryID: UUID? = TaskCategory.workID {
        didSet { defaults.set(selectedCategoryID?.uuidString ?? "all", forKey: "todoCategory") }
    }
    @Published var selectedQuadrant: Quadrant? {
        didSet { defaults.set(selectedQuadrant?.rawValue ?? "all", forKey: "todoQuadrant") }
    }
    @Published var showingCompleted = false

    let fileURL: URL
    private let defaults: UserDefaults
    private var storageAvailable = true

    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HangTodo", isDirectory: true).appendingPathComponent("tasks.json")
    }

    init(fileURL: URL = TaskStore.defaultFileURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let archive = try JSONDecoder().decode(TaskArchive.self, from: Data(contentsOf: fileURL))
                try archive.validate()
                tasks = archive.tasks
                categories = archive.categories
            } catch {
                storageAvailable = false
                errorMessage = F("无法读取任务：%@\n%@", error.localizedDescription, fileURL.path)
            }
        }
        if let saved = defaults.string(forKey: "todoCategory") {
            if saved == "all" { selectedCategoryID = nil }
            else if let id = UUID(uuidString: saved), categories.contains(where: { $0.id == id }) {
                selectedCategoryID = id
            }
        }
        selectedQuadrant = defaults.string(forKey: "todoQuadrant").flatMap(Quadrant.init(rawValue:))
    }

    var visibleTasks: [TodoTask] {
        tasks.enumerated().filter {
            $0.element.isCompleted == showingCompleted
            && (selectedCategoryID == nil || $0.element.categoryID == selectedCategoryID)
            && (showingCompleted || selectedQuadrant == nil || $0.element.quadrant == selectedQuadrant)
        }.sorted {
            if showingCompleted, $0.element.completedAt != $1.element.completedAt {
                return ($0.element.completedAt ?? .distantPast) > ($1.element.completedAt ?? .distantPast)
            }
            if $0.element.quadrant != $1.element.quadrant { return $0.element.quadrant.rank < $1.element.quadrant.rank }
            // The saved array order is the manual priority, including after reopening.
            return $0.offset < $1.offset
        }.map(\.element)
    }

    func count(in quadrant: Quadrant? = nil, completed: Bool = false) -> Int {
        tasks.filter {
            $0.isCompleted == completed
            && (selectedCategoryID == nil || $0.categoryID == selectedCategoryID)
            && (quadrant == nil || $0.quadrant == quadrant)
        }.count
    }

    func categoryCount(_ id: UUID?, completed: Bool = false) -> Int {
        tasks.filter { $0.isCompleted == completed && (id == nil || $0.categoryID == id) }.count
    }

    func canDrop(_ id: UUID, at destination: TaskDestination) -> Bool {
        guard let source = tasks.first(where: { $0.id == id }) else { return false }
        switch destination {
        case .task(let targetID):
            guard targetID != id, let target = tasks.first(where: { $0.id == targetID }) else { return false }
            return !source.isCompleted && !target.isCompleted && source.quadrant == target.quadrant
        case .category(let categoryID): return categories.contains { $0.id == categoryID }
        case .quadrant, .pending, .completed: return true
        }
    }

    @discardableResult
    func dropTask(_ id: UUID, at destination: TaskDestination, before: Bool = true) -> Bool {
        guard canDrop(id, at: destination), let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        if destination == .completed { return setCompleted(id, true) }
        if destination == .pending { return setCompleted(id, false) }
        let source = tasks[index]
        if case .category(let categoryID) = destination, source.categoryID == categoryID { return true }
        if case .quadrant(let quadrant) = destination, source.quadrant == quadrant { return setCompleted(id, false) }
        let saved = commit { archive in
            var moving = archive.tasks.remove(at: index)
            switch destination {
            case .task(let targetID):
                let targetIndex = archive.tasks.firstIndex(where: { $0.id == targetID })!
                archive.tasks.insert(moving, at: targetIndex + (before ? 0 : 1))
            case .quadrant(let quadrant):
                moving.quadrant = quadrant
                moving.completedAt = nil
                insertAtEndOfGroup(moving, into: &archive.tasks)
            case .category(let categoryID):
                moving.categoryID = categoryID
                insertAtEndOfGroup(moving, into: &archive.tasks)
            case .pending, .completed: break
            }
        }
        if saved, pendingUndo?.taskID == id { pendingUndo = nil }
        return saved
    }

    private func insertAtEndOfGroup(_ task: TodoTask, into tasks: inout [TodoTask]) {
        let last = tasks.lastIndex { $0.categoryID == task.categoryID && $0.quadrant == task.quadrant && $0.isCompleted == task.isCompleted }
        tasks.insert(task, at: last.map { $0 + 1 } ?? tasks.endIndex)
    }

    func categoryName(_ id: UUID) -> String {
        id == TaskCategory.workID ? L("工作") : categories.first(where: { $0.id == id })?.name ?? L("工作")
    }

    @discardableResult
    func addTask(title: String, notes: String = "", categoryID: UUID = TaskCategory.workID,
                 quadrant: Quadrant = .importantUrgent) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, categories.contains(where: { $0.id == categoryID }) else { return false }
        return commit { archive in
            archive.tasks.append(TodoTask(id: UUID(), title: title, notes: notes,
                                          categoryID: categoryID, quadrant: quadrant, createdAt: Date()))
        }
    }

    @discardableResult
    func updateTask(_ id: UUID, title: String, notes: String, categoryID: UUID, quadrant: Quadrant) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, categories.contains(where: { $0.id == categoryID }),
              let i = tasks.firstIndex(where: { $0.id == id }) else { return false }
        let saved = commit { archive in
            archive.tasks[i].title = title
            archive.tasks[i].notes = notes
            archive.tasks[i].categoryID = categoryID
            archive.tasks[i].quadrant = quadrant
        }
        if saved, pendingUndo?.taskID == id { pendingUndo = nil }
        return saved
    }

    @discardableResult
    func setCompleted(_ id: UUID, _ completed: Bool) -> Bool {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return false }
        if tasks[i].isCompleted == completed { return true }
        let previousDate = tasks[i].completedAt
        let nextDate: Date? = completed ? Date() : nil
        guard commit({ $0.tasks[i].completedAt = nextDate }) else { return false }
        let undo = CompletionUndo(taskID: id, previousDate: previousDate, expectedDate: nextDate,
                                  message: completed ? "任务已完成" : "已重新打开，回到原分类和象限")
        pendingUndo = undo
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard self?.pendingUndo?.id == undo.id else { return }
            self?.pendingUndo = nil
        }
        return true
    }

    @discardableResult
    func undoCompletion() -> Bool {
        guard let undo = pendingUndo, let i = tasks.firstIndex(where: { $0.id == undo.taskID }),
              tasks[i].completedAt == undo.expectedDate else { return false }
        guard commit({ $0.tasks[i].completedAt = undo.previousDate }) else { return false }
        pendingUndo = nil
        return true
    }

    @discardableResult
    func deleteTask(_ id: UUID) -> Bool {
        guard tasks.contains(where: { $0.id == id }) else { return false }
        let saved = commit { $0.tasks.removeAll { $0.id == id } }
        if saved, pendingUndo?.taskID == id { pendingUndo = nil }
        return saved
    }

    func categoryNameIsAvailable(_ name: String, excluding id: UUID? = nil) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !categories.contains {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    @discardableResult
    func addCategory(_ name: String) -> Bool {
        guard categoryNameIsAvailable(name) else { return false }
        return commit { $0.categories.append(TaskCategory(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines))) }
    }

    @discardableResult
    func renameCategory(_ id: UUID, to name: String) -> Bool {
        guard id != TaskCategory.workID, categoryNameIsAvailable(name, excluding: id),
              let i = categories.firstIndex(where: { $0.id == id }) else { return false }
        return commit { $0.categories[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    @discardableResult
    func deleteCategory(_ id: UUID) -> Bool {
        guard id != TaskCategory.workID, categories.contains(where: { $0.id == id }) else { return false }
        let saved = commit { archive in
            archive.categories.removeAll { $0.id == id }
            for i in archive.tasks.indices where archive.tasks[i].categoryID == id {
                archive.tasks[i].categoryID = TaskCategory.workID
            }
        }
        if saved, selectedCategoryID == id { selectedCategoryID = TaskCategory.workID }
        return saved
    }

    // Save before publishing, so a disk error cannot silently lose a task.
    private func commit(_ change: (inout TaskArchive) -> Void) -> Bool {
        guard storageAvailable else {
            errorMessage = F("任务文件无法读取，暂时不能修改。原文件已保留：\n%@", fileURL.path)
            return false
        }
        var archive = TaskArchive(categories: categories, tasks: tasks)
        change(&archive)
        do {
            try archive.validate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(archive)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            categories = archive.categories
            tasks = archive.tasks
            return true
        } catch {
            errorMessage = F("未能保存任务，操作未生效：%@", error.localizedDescription)
            return false
        }
    }
}
