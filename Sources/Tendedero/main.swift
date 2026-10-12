import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let instanceLock: InstanceLock
    do {
        guard let acquired = try InstanceLock.acquire(at: SingleInstance.lockURL) else {
            SingleInstance.revealExisting()
            exit(0)
        }
        instanceLock = acquired
    } catch {
        let alert = NSAlert()
        alert.messageText = L("无法启动 HangTodo")
        alert.informativeText = F("无法锁定应用：%@", error.localizedDescription)
        alert.addButton(withTitle: L("好"))
        alert.runModal()
        exit(1)
    }
    var testStore: TaskStore?
    #if DEBUG
    // UI checks use a separate store and app bundle, never the owner's tasks.
    if let index = CommandLine.arguments.firstIndex(of: "--ui-test-store"),
       CommandLine.arguments.indices.contains(index + 1) {
        testStore = TaskStore(fileURL: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    }
    #endif
    let delegate = AppDelegate(store: testStore)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime((delegate, instanceLock)) { app.run() }
}
