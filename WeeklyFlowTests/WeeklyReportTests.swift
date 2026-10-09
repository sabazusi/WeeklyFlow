import AppKit
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

    func testCompletedHistoryGroupsByMonday() {
        let firstWeek = TaskItem(title: "先週")
        firstWeek.move(to: .completed, at: date(2026, 10, 4, 23))
        let monday = TaskItem(title: "月曜")
        monday.move(to: .completed, at: date(2026, 10, 5))
        let sunday = TaskItem(title: "日曜")
        sunday.move(to: .completed, at: date(2026, 10, 11, 23))
        let groups = WeeklyReport.completedGroups(from: [firstWeek, monday, sunday], calendar: calendar)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].tasks.map(\.title), ["日曜", "月曜"])
        XCTAssertEqual(WeeklyReport.weekLabel(for: groups[0].interval, calendar: calendar), "2026/10/05〜2026/10/11")
        XCTAssertEqual(groups[1].tasks.map(\.title), ["先週"])
    }

    func testManualOrderAndMoveBackToInbox() {
        let older = TaskItem(title: "古いタスク", createdAt: date(2026, 10, 5))
        let newer = TaskItem(title: "新しいタスク", createdAt: date(2026, 10, 6))
        XCTAssertEqual(TaskOrdering.sorted([older, newer]).map(\.title), ["新しいタスク", "古いタスク"])

        TaskOrdering.apply([older, newer])
        XCTAssertEqual(TaskOrdering.sorted([newer, older]).map(\.title), ["古いタスク", "新しいタスク"])

        older.move(to: .active)
        older.move(to: .inbox)
        TaskOrdering.placeFirst(older, among: [newer])
        XCTAssertEqual(older.status, .inbox)
        XCTAssertEqual(TaskOrdering.sorted([newer, older]).map(\.title), ["古いタスク", "新しいタスク"])
    }

    func testTaskSurvivesReopeningLocalStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Tasks.store")

        do {
            let container = try ModelContainer(for: TaskItem.self, configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(container)
            let task = TaskItem(title: "保存されたタスク")
            task.sortOrder = 3
            context.insert(task)
            try context.save()
        }

        let reopened = try ModelContainer(for: TaskItem.self, configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(reopened)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertTrue(tasks.contains { $0.title == "保存されたタスク" })
        XCTAssertEqual(tasks.first?.sortOrder, 3)
    }
}

final class DoubleShiftTests: XCTestCase {
    private func shift(_ detector: inout DoubleShiftDetector, _ pressed: Bool, at time: TimeInterval, keyCode: UInt16 = 56) -> Bool {
        detector.accept(
            type: .flagsChanged,
            keyCode: keyCode,
            modifiers: pressed ? .shift : [],
            timestamp: time
        )
    }

    func testQuickDoubleShiftTriggersOnce() {
        var detector = DoubleShiftDetector()
        XCTAssertFalse(shift(&detector, true, at: 1.0))
        XCTAssertFalse(shift(&detector, false, at: 1.1))
        XCTAssertFalse(shift(&detector, true, at: 1.3))
        XCTAssertTrue(shift(&detector, false, at: 1.4))
        XCTAssertFalse(shift(&detector, true, at: 1.6))
    }

    func testSlowOrHeldShiftDoesNotTrigger() {
        var detector = DoubleShiftDetector()
        XCTAssertFalse(shift(&detector, true, at: 1.0))
        XCTAssertFalse(shift(&detector, false, at: 1.5))
        XCTAssertFalse(shift(&detector, true, at: 1.7))
        XCTAssertFalse(shift(&detector, false, at: 1.8))

        detector.reset()
        XCTAssertFalse(shift(&detector, true, at: 2.0))
        XCTAssertFalse(shift(&detector, false, at: 2.1))
        XCTAssertFalse(shift(&detector, true, at: 2.7))
        XCTAssertFalse(shift(&detector, false, at: 2.8))
    }

    func testOtherKeyAndOppositeShiftCancelSequence() {
        var detector = DoubleShiftDetector()
        XCTAssertFalse(shift(&detector, true, at: 1.0))
        XCTAssertFalse(shift(&detector, false, at: 1.1))
        XCTAssertFalse(detector.accept(type: .keyDown, keyCode: 0, modifiers: [], timestamp: 1.2))
        XCTAssertFalse(shift(&detector, true, at: 1.3))
        XCTAssertFalse(shift(&detector, false, at: 1.4))

        detector.reset()
        XCTAssertFalse(shift(&detector, true, at: 2.0))
        XCTAssertFalse(shift(&detector, false, at: 2.1))
        XCTAssertFalse(shift(&detector, true, at: 2.2, keyCode: 60))
        XCTAssertFalse(shift(&detector, false, at: 2.3, keyCode: 60))
    }
}
