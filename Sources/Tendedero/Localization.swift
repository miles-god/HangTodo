import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans", english = "en"
    var id: String { rawValue }
    var name: String { self == .chinese ? "中文" : "English" }
    var locale: Locale { Locale(identifier: self == .chinese ? "zh_CN" : "en_US") }
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .chinese
    }
}

enum Localizer {
    static let english: [String: String] = [
        "工作": "Work", "全部分类": "All categories", "全部": "All", "全部待办": "All pending",
        "全部象限": "All quadrants", "重要且紧急": "Important & urgent", "重要不紧急": "Important, not urgent",
        "紧急不重要": "Urgent, not important", "不重要不紧急": "Neither important nor urgent",
        "重要紧急": "Urgent + important", "重要不急": "Important", "紧急不重": "Urgent", "其他": "Other",
        "待办": "Pending", "已完成": "Completed", "已完成 %d": "Completed %d", "新增": "Add",
        "新增任务": "Add task", "选择任务分类": "Choose a category", "显示全部分类": "Show all categories",
        "%@，%d 项待办": "%@, %d pending", "分类%@，%d 项待办": "Category %@, %d pending",
        "%@，拖入可以%@": "%@ · Drop to %@",
        "重新打开任务": "reopen the task", "修改象限": "Change quadrant", "移动到分类": "Move to category",
        "拖入更改任务分类，保留完成状态": "Drop to move category and keep completion status",
        "返回待办任务": "Return to pending tasks", "查看已完成任务，可以重新打开": "View and reopen completed tasks",
        "这里还没有已完成的任务": "No completed tasks here yet", "这根绳上暂时没有待办": "No pending tasks on this line",
        "返回待办": "Back to pending", "挂上一个新任务": "Hang a new task", "撤销": "Undo",
        "上一组任务": "Previous tasks", "下一组任务": "Next tasks", "横向滚动查看更多": "Scroll for more",
        "任务已完成": "Task completed",
        "已重新打开，回到原分类和象限": "Reopened in its original category and quadrant",
        "完成": "Complete", "重新打开": "Reopen", "标记完成": "Mark completed",
        "重新打开，回到原分类和象限": "Reopen in its original category and quadrant",
        "标记完成，随后可以撤销": "Complete this task; you can undo it",
        "%@：%@": "%@: %@", "编辑…": "Edit…", "删除任务…": "Delete task…",
        "任务操作：%@": "Task actions: %@", "编辑任务：%@": "Edit task: %@",
        "点击编辑，拖动排序或移动到象限、分类和已完成。": "Click to edit. Drag to reorder or move to a quadrant, category or Completed.",
        "点击查看完整备注": "Click to view all notes",
        "挂上新任务": "New task", "编辑任务": "Edit task", "把下一件事挂上绳": "Hang your next task",
        "整理这项任务": "Edit this task", "任务标题": "Task title", "要做什么？": "What needs doing?",
        "分类": "Category", "四象限": "Quadrant", "备注（可选）": "Notes (optional)", "任务备注": "Task notes",
        "这项任务已完成，可在“已完成”视图中重新打开。": "This task is completed. You can reopen it from Completed.",
        "保存在这台 Mac 上": "Saved on this Mac", "取消": "Cancel", "挂上去": "Hang task", "保存": "Save",
        "无法保存，请检查任务是否仍然存在。": "Couldn't save. Check that the task still exists.",
        "管理分类": "Manage categories", "管理分类…": "Manage categories…", "给任务一个归属": "Organize your tasks",
        "工作是默认分类。删除其他分类时，任务会转入工作。": "Work is the default. Tasks move to Work when you delete another category.",
        "新分类名称": "New category name", "分类名称不能为空或重复。": "Use a non-empty, unique category name.",
        "删除分类“%@”？": "Delete category “%@”?", "删除分类": "Delete category",
        "里面的待办和已完成任务都会转入“工作”，任务内容和状态将保留。": "Pending and completed tasks will move to Work with their content and status preserved.",
        "默认分类": "Default category", "分类名称": "Category name", "重命名分类：%@": "Rename category: %@",
        "删除分类：%@": "Delete category: %@", "小": "Small", "中": "Medium", "大": "Large",
        "空格": "Space", "按下新的快捷键": "Press the new shortcut", "Escape 取消，Delete 移除快捷键。": "Escape cancels. Delete removes the shortcut.",
        "更改快捷键": "Change shortcut", "未设置": "Not set", "HangTodo · 待办晾衣绳": "HangTodo · Task clothesline",
        "快捷键 %@ 无法注册，请在设置中选择其他组合。": "Couldn't register %@. Choose another shortcut in Settings.",
        "快捷键 %@ 无法注册，请选择其他组合。原快捷键已保留。": "Couldn't register %@. Choose another combination. Your previous shortcut is preserved.",
        "删除这项任务？": "Delete this task?", "“%@”将被删除。如果只是做完了，请选择标记完成。": "“%@” will be deleted. To finish a task, mark it completed instead.",
        "删除任务": "Delete task", "操作未能完成": "Couldn't complete this action", "好": "OK",
        "设置": "Settings", "设置…": "Settings…", "退出 HangTodo": "Quit HangTodo",
        "语言": "Language", "外观": "Appearance", "便签大小": "Card size", "显示与启动": "Display & startup",
        "鼠标停在菜单栏时展开": "Show when the pointer rests in the menu bar", "在全屏应用上显示": "Show over full-screen apps",
        "登录时启动": "Launch at login", "快捷键": "Keyboard shortcut", "更改…": "Change…",
        "鼠标离开时保持展开；点击空白或切换窗口时收起。": "Stays open when the pointer leaves. Click outside or switch windows to hide.",
        "界面语言立即生效。": "The interface updates immediately.", "无法更改登录启动设置：%@": "Couldn't change launch-at-login settings: %@",
        "任务文件格式不正确或版本不受支持。原文件已保留，请检查文件后重新启动。": "The task file is invalid or uses an unsupported version. The original is preserved; check it and restart.",
        "无法读取任务：%@\n%@": "Couldn't read tasks: %@\n%@",
        "任务文件无法读取，暂时不能修改。原文件已保留：\n%@": "The task file couldn't be read. Changes are disabled and the original is preserved:\n%@",
        "未能保存任务，操作未生效：%@": "Couldn't save tasks. No changes were made: %@",
        "无法启动 HangTodo": "Couldn't start HangTodo", "无法锁定应用：%@": "Couldn't lock the application: %@"
    ]

    static func text(_ key: String, language: AppLanguage) -> String {
        language == .english ? english[key] ?? key : key
    }
    static func format(_ key: String, language: AppLanguage, arguments: [CVarArg]) -> String {
        String(format: text(key, language: language), locale: language.locale, arguments: arguments)
    }
}

func L(_ key: String) -> String { Localizer.text(key, language: .current) }
func F(_ key: String, _ arguments: CVarArg...) -> String {
    Localizer.format(key, language: .current, arguments: arguments)
}
