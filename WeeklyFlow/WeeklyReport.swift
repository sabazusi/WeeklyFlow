import Foundation

struct CompletedWeekGroup: Identifiable {
    let interval: DateInterval
    let tasks: [TaskItem]

    var id: Date { interval.start }
}

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

    static func completedGroups(from tasks: [TaskItem], calendar: Calendar = .current) -> [CompletedWeekGroup] {
        var groups: [Date: [TaskItem]] = [:]
        for task in tasks where task.status == .completed {
            guard let completedAt = task.completedAt else { continue }
            let weekStart = interval(containing: completedAt, calendar: calendar).start
            groups[weekStart, default: []].append(task)
        }
        return groups.keys.sorted(by: >).map { start in
            let ordered = groups[start, default: []].sorted {
                ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
            }
            return CompletedWeekGroup(interval: interval(containing: start, calendar: calendar), tasks: ordered)
        }
    }

    static func weekLabel(for interval: DateInterval, calendar: Calendar = .current) -> String {
        let endDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy/MM/dd"
        return "\(formatter.string(from: interval.start))〜\(formatter.string(from: endDay))"
    }

    static func copyText(for tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> String {
        let week = interval(containing: now, calendar: calendar)
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateFormat = "MM/dd HH:mm"

        let header = "今週完了したタスク（\(weekLabel(for: week, calendar: calendar))）：\(tasks.count)件"
        guard !tasks.isEmpty else { return header + "\n今週完了したタスクはありません。" }
        let lines = tasks.compactMap { task -> String? in
            guard let completedAt = task.completedAt else { return nil }
            return "- \(dateFormatter.string(from: completedAt)) \(task.title)"
        }
        return ([header] + lines).joined(separator: "\n")
    }
}
