import AppKit

struct TaskCardMetrics: Equatable {
    let height: CGFloat
    let noteLines: Int
    let notesTruncated: Bool

    static func measure(_ task: TodoTask, width: CGFloat, scale: CGFloat, maximumHeight: CGFloat) -> TaskCardMetrics {
        let textWidth = max(1, width - 24)
        let titleFont = NSFont.systemFont(ofSize: 14 * scale, weight: .medium)
        let noteFont = NSFont.systemFont(ofSize: 11 * scale)
        let titleHeight = min(textHeight(task.title, width: max(1, textWidth - 66), font: titleFont), ceil(titleFont.boundingRectForFont.height) * 3 + 4)
        let titleOnly = 24 + max(26, titleHeight)
        let notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return TaskCardMetrics(height: ceil(titleOnly), noteLines: 0, notesTruncated: false) }
        // Metadata and row gaps appear only when the card has notes.
        let base = titleOnly + 16 + 16
        let measuredLineHeight = ceil(noteFont.boundingRectForFont.height)
        // SwiftUI's fallback fonts (including Chinese) need a little more leading.
        let lineHeight = measuredLineHeight + 2
        let measured = textHeight(notes, width: textWidth, font: noteFont)
        let availableLines = max(1, Int((maximumHeight - base - 6) / lineHeight))
        let fullLines = max(notes.components(separatedBy: "\n").count, Int(ceil(measured / measuredLineHeight)))
        let lines = min(fullLines, availableLines)
        return TaskCardMetrics(height: ceil(base + 6 + CGFloat(lines) * lineHeight), noteLines: lines, notesTruncated: fullLines > lines)
    }

    private static func textHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        ceil((text as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
             options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height)
    }
}

struct CardMotionProfile: Equatable {
    let initialDelay: Double
    let interval: Double
    let amplitude: Double
    let stiffness: Double
    let damping: Double

    init(id: UUID) {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        var seed = bytes.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        seed = (seed ^ (seed >> 30)) &* 0xbf58476d1ce4e5b9
        seed = (seed ^ (seed >> 27)) &* 0x94d049bb133111eb
        seed ^= seed >> 31
        initialDelay = Double(seed % 3000) / 1000
        interval = 7 + Double((seed >> 8) % 8000) / 1000
        amplitude = (1.3 + Double((seed >> 16) % 1700) / 1000) * (seed % 2 == 0 ? 1 : -1)
        stiffness = 28 + Double((seed >> 24) % 20)
        damping = 2.8 + Double((seed >> 32) % 160) / 100
    }
}
