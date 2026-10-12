import AppKit

struct ForegroundWindow: Equatable {
    let processID: pid_t
    let windowID: CGWindowID

    static func current() -> ForegroundWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let window = windows.first(where: {
                  ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier
                  && ($0[kCGWindowLayer as String] as? Int) == 0
              }), let id = window[kCGWindowNumber as String] as? UInt32 else { return nil }
        return ForegroundWindow(processID: app.processIdentifier, windowID: id)
    }
}
struct WindowSwitchTracker {
    var baseline: ForegroundWindow?
    mutating func changed(to window: ForegroundWindow?) -> Bool {
        guard let window else { return false }
        let changed = baseline != nil && baseline != window
        baseline = window
        return changed
    }
}

enum VisibilityPolicy {
    static func shouldHideForClick(at point: CGPoint, controls: [CGRect], busy: Bool) -> Bool {
        !busy && !controls.contains { $0.insetBy(dx: -3, dy: -3).contains(point) }
    }
}
