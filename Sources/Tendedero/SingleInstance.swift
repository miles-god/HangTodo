import AppKit
import Darwin

final class InstanceLock {
    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }

    static func acquire(at url: URL) throws -> InstanceLock? {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = url.path.withCString { Darwin.open($0, O_CREAT | O_RDWR, 0o600) }
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return InstanceLock(descriptor: descriptor) }
        let failure = errno
        Darwin.close(descriptor)
        if failure == EWOULDBLOCK { return nil }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
    }

    deinit { Darwin.close(descriptor) }
}

enum SingleInstance {
    static let revealNotification = Notification.Name("app.hangtodo.revealLine")
    static var identifier: String { Bundle.main.bundleIdentifier ?? "app.hangtodo.HangTodo" }
    static var lockURL: URL {
        let safe = identifier.map { $0.isLetter || $0.isNumber || ".-_".contains($0) ? $0 : "_" }
        return TaskStore.defaultFileURL.deletingLastPathComponent().appendingPathComponent(".\(String(safe)).lock")
    }
    static var existing: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }
    static func revealExisting() {
        existing?.activate(options: [])
        DistributedNotificationCenter.default().postNotificationName(revealNotification, object: identifier,
                                                                     userInfo: nil, deliverImmediately: true)
    }
}
