import Foundation
import SwiftData

enum TaskStatus: String, CaseIterable {
    case inbox
    case active
    case completed

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .active: "実行リスト"
        case .completed: "完了"
        }
    }
}

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var statusRaw: String
    var statusBeforeCompletionRaw: String?
    var createdAt: Date
    var completedAt: Date?
    var sortOrder: Int?

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }

    init(title: String, notes: String = "", createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.statusRaw = TaskStatus.inbox.rawValue
        self.statusBeforeCompletionRaw = nil
        self.createdAt = createdAt
        self.completedAt = nil
        self.sortOrder = nil
    }

    func move(to newStatus: TaskStatus, at date: Date = .now) {
        guard status != newStatus else { return }
        if newStatus == .completed {
            statusBeforeCompletionRaw = status.rawValue
        } else {
            statusBeforeCompletionRaw = nil
        }
        status = newStatus
        completedAt = newStatus == .completed ? date : nil
    }

    func undoCompletion() {
        guard status == .completed else { return }
        status = TaskStatus(rawValue: statusBeforeCompletionRaw ?? "") ?? .active
        statusBeforeCompletionRaw = nil
        completedAt = nil
    }
}

enum TaskOrdering {
    static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { left, right in
            switch (left.sortOrder, right.sortOrder) {
            case let (leftOrder?, rightOrder?) where leftOrder != rightOrder:
                return leftOrder < rightOrder
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
                return left.id.uuidString < right.id.uuidString
            }
        }
    }

    static func placeFirst(_ task: TaskItem, among existing: [TaskItem]) {
        let remaining = sorted(existing.filter { $0.id != task.id })
        apply([task] + remaining)
    }

    static func apply(_ tasks: [TaskItem]) {
        for (index, task) in tasks.enumerated() {
            task.sortOrder = index
        }
    }
}
