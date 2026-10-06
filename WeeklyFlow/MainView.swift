import AppKit
import Combine
import ServiceManagement
import SwiftData
import SwiftUI

private enum TaskSection: String, CaseIterable {
    case inbox
    case active
    case weekly
    case completed
    case settings

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .active: "実行リスト"
        case .weekly: "今週やったこと"
        case .completed: "完了履歴"
        case .settings: "設定"
        }
    }

    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .active: "list.bullet.circle"
        case .weekly: "calendar.badge.checkmark"
        case .completed: "checkmark.circle"
        case .settings: "gearshape"
        }
    }
}

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var section: TaskSection = .inbox
    @State private var newTitle = ""
    @State private var editingTask: TaskItem?
    @State private var errorMessage: String?
    @State private var currentDate = Date()

    private var weekTasks: [TaskItem] {
        WeeklyReport.completedTasks(from: tasks, now: currentDate)
    }

    private var visibleTasks: [TaskItem] {
        switch section {
        case .inbox: tasks.filter { $0.status == .inbox }
        case .active: tasks.filter { $0.status == .active }
        case .completed: tasks.filter { $0.status == .completed }
        case .weekly: weekTasks
        case .settings: []
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if section == .settings {
                    settingsContent
                } else {
                    if section == .inbox || section == .active {
                        quickAdd
                    }
                    taskContent
                }
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .sheet(item: $editingTask) { task in
            TaskEditor(task: task) { title, notes in
                task.title = title
                task.notes = notes
                return save()
            } onDelete: {
                modelContext.delete(task)
                let saved = save()
                if saved { editingTask = nil }
                return saved
            }
        }
        .alert("保存できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            currentDate = .now
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            currentDate = date
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WeeklyFlow")
                .font(.title3.bold())
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            ForEach(TaskSection.allCases, id: \.self) { item in
                Button {
                    currentDate = .now
                    section = item
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(section == item ? Color.accentColor.opacity(0.16) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button("終了") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(12)
        }
        .padding(12)
        .frame(width: 198)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title).font(.title2.bold())
                if section == .weekly {
                    Text("月曜から日曜までに完了したタスク · \(weekTasks.count)件")
                        .foregroundStyle(.secondary)
                } else if section != .settings {
                    Text("\(visibleTasks.count)件")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if section == .weekly {
                Button("コピー", systemImage: "doc.on.doc") {
                    let text = WeeklyReport.copyText(for: weekTasks, now: currentDate)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
        .padding(20)
    }

    private var quickAdd: some View {
        HStack {
            TextField("新しいタスク", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTask)
            Button("追加", action: addTask)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var taskContent: some View {
        Group {
            if visibleTasks.isEmpty {
                ContentUnavailableView(
                    section == .weekly ? "今週の完了タスクはありません" : "タスクはありません",
                    systemImage: section == .weekly ? "calendar" : "checkmark.circle"
                )
            } else {
                List {
                    ForEach(visibleTasks) { task in
                        taskRow(task)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                if task.status == .completed {
                    task.undoCompletion()
                } else {
                    task.move(to: .completed)
                }
                save()
            } label: {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(task.status == .completed ? "完了を取り消す" : "完了にする")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(.body.weight(.medium))
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                if let completedAt = task.completedAt {
                    Text(completedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if task.status == .inbox {
                Button("実行リストへ") {
                    task.move(to: .active)
                    save()
                }
                .controlSize(.small)
            }
            Button("編集", systemImage: "square.and.pencil") { editingTask = task }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 7)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("ログイン時に自動起動", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: setLaunchAtLogin
            ))
            Text("タスクはこのMac内に保存されます。パネルを閉じてもメニューバーから再表示できます。")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let task = TaskItem(title: title)
        if section == .active { task.move(to: .active) }
        modelContext.insert(task)
        if save() { newTitle = "" }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var confirmingDelete = false
    let onSave: (String, String) -> Bool
    let onDelete: () -> Bool

    init(task: TaskItem, onSave: @escaping (String, String) -> Bool, onDelete: @escaping () -> Bool) {
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("タスクを編集").font(.title2.bold())
            TextField("タイトル", text: $title)
            TextEditor(text: $notes)
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Button("削除", role: .destructive) { confirmingDelete = true }
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("保存") {
                    if onSave(title.trimmingCharacters(in: .whitespacesAndNewlines), notes) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .confirmationDialog("このタスクを削除しますか？", isPresented: $confirmingDelete) {
            Button("削除", role: .destructive) {
                if onDelete() { dismiss() }
            }
        }
    }
}
