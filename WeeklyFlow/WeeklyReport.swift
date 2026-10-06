import Foundation

enum WeeklyReport {
    static func interval(containing date: Date = .now, calendar inputCalendar: Calendar = .current) -> DateInterval {
        var calendar = inputCalendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar.dateInterval(of: .weekOfYear, for: date)!
    }

    static func completedTasks(
        from tasks: [TaskItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TaskItem] {
        let week = interval(containing: now, calendar: calendar)
        return tasks.filter { task in
            guard task.status == .completed, let completedAt = task.completedAt else { return false }
            return completedAt >= week.start && completedAt < week.end
        }
        .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    static func copyText(for tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> String {
        let week = interval(containing: now, calendar: calendar)
        let endDay = calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.end
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy/MM/dd"
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateFormat = "MM/dd HH:mm"

        let header = "今週完了したタスク（\(dayFormatter.string(from: week.start))〜\(dayFormatter.string(from: endDay))）：\(tasks.count)件"
        guard !tasks.isEmpty else { return header + "\n今週完了したタスクはありません。" }
        let lines = tasks.compactMap { task -> String? in
            guard let completedAt = task.completedAt else { return nil }
            return "- \(dateFormatter.string(from: completedAt)) \(task.title)"
        }
        return ([header] + lines).joined(separator: "\n")
    }
}
