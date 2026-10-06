import Foundation
import SwiftData
import XCTest
@testable import WeeklyFlow

final class WeeklyReportTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testWeekIncludesMondayAndExcludesNextMonday() {
        let monday = TaskItem(title: "月曜の作業")
        monday.move(to: .completed, at: date(2026, 10, 5))
        let sunday = TaskItem(title: "日曜の作業")
        sunday.move(to: .completed, at: date(2026, 10, 11, 23))
        let nextMonday = TaskItem(title: "翌週の作業")
        nextMonday.move(to: .completed, at: date(2026, 10, 12))
        let result = WeeklyReport.completedTasks(
            from: [monday, sunday, nextMonday],
            now: date(2026, 10, 6),
            calendar: calendar
        )
        XCTAssertEqual(result.map(\.title), ["日曜の作業", "月曜の作業"])
    }

    func testUndoClearsCompletionAndRestoresInbox() {
        let task = TaskItem(title: "確認")
        task.move(to: .completed, at: date(2026, 10, 6))
        task.undoCompletion()
        XCTAssertEqual(task.status, .inbox)
        XCTAssertNil(task.completedAt)
    }

    func testCopyTextContainsDatesAndTitles() {
        let task = TaskItem(title: "資料作成")
        task.move(to: .completed, at: date(2026, 10, 6, 14))
        let text = WeeklyReport.copyText(for: [task], now: date(2026, 10, 6), calendar: calendar)
        XCTAssertTrue(text.contains("2026/10/05〜2026/10/11"))
        XCTAssertTrue(text.contains("- 10/06 14:00 資料作成"))
    }

    func testTaskSurvivesReopeningLocalStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Tasks.store")

        do {
            let container = try ModelContainer(for: TaskItem.self, configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(container)
            context.insert(TaskItem(title: "保存されたタスク"))
            try context.save()
        }

        let reopened = try ModelContainer(for: TaskItem.self, configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(reopened)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertTrue(tasks.contains { $0.title == "保存されたタスク" })
    }
}
