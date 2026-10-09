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
    let hotKeyManager: GlobalHotKeyManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var section: TaskSection = .inbox
    @State private var newTitle = ""
    @State private var editingTask: TaskItem?
    @State private var errorMessage: String?
    @State private var currentDate = Date()
    @State private var launchStatus = SMAppService.mainApp.status
    @State private var shortcut: GlobalShortcut?
    @State private var recordingShortcut = false
    @State private var shortcutMonitor: Any?

    private var weekTasks: [TaskItem] {
        WeeklyReport.completedTasks(from: tasks, now: currentDate)
    }

    private var visibleTasks: [TaskItem] {
        switch section {
        case .inbox: TaskOrdering.sorted(tasks.filter { $0.status == .inbox })
        case .active: TaskOrdering.sorted(tasks.filter { $0.status == .active })
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
            launchStatus = SMAppService.mainApp.status
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            currentDate = date
        }
        .onAppear {
            launchStatus = SMAppService.mainApp.status
            shortcut = hotKeyManager.shortcut
        }
        .onDisappear { stopRecordingShortcut() }
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
                    HStack {
                        Label(item.title, systemImage: item.symbol)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(section == item ? Color.accentColor.opacity(0.16) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
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
            if section == .completed {
                completedHistory
            } else if visibleTasks.isEmpty {
                ContentUnavailableView(
                    section == .weekly ? "今週の完了タスクはありません" : "タスクはありません",
                    systemImage: section == .weekly ? "calendar" : "checkmark.circle"
                )
            } else {
                List {
                    ForEach(visibleTasks) { task in
                        taskRow(task)
                    }
                    .onMove(perform: section == .inbox || section == .active ? reorderTasks : nil)
                }
                .listStyle(.plain)
            }
        }
    }

    private var completedHistory: some View {
        let groups = WeeklyReport.completedGroups(from: tasks)
        return Group {
            if groups.isEmpty {
                ContentUnavailableView("タスクはありません", systemImage: "checkmark.circle")
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.tasks) { task in
                                taskRow(task)
                            }
                        } header: {
                            Text("\(WeeklyReport.weekLabel(for: group.interval)) · \(group.tasks.count)件")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func reorderTasks(from source: IndexSet, to destination: Int) {
        var ordered = visibleTasks
        ordered.move(fromOffsets: source, toOffset: destination)
        TaskOrdering.apply(ordered)
        save()
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if task.status != .completed {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .help("ドラッグして並べ替え")
            }
            Button {
                if task.status == .completed {
                    task.undoCompletion()
                    TaskOrdering.placeFirst(task, among: tasks.filter { $0.status == task.status })
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
                    move(task, to: .active)
                }
                .controlSize(.small)
            } else if task.status == .active {
                Button("Inboxへ") {
                    move(task, to: .inbox)
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
                get: { launchStatus == .enabled || launchStatus == .requiresApproval },
                set: setLaunchAtLogin
            ))
            if launchStatus == .requiresApproval {
                Text("自動起動の有効化には、システム設定の「ログイン項目」でWeeklyFlowを許可してください。")
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("全アプリ共通のショートカット")
                Spacer()
                Button(recordingShortcut ? "キーを押してください…" : shortcut?.displayName ?? "設定") {
                    startRecordingShortcut()
                }
                if shortcut != nil {
                    Button("解除") {
                        stopRecordingShortcut()
                        do {
                            try hotKeyManager.update(nil)
                            shortcut = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            Text("修飾キーを2つ以上と英数字を組み合わせます。Escで設定を中止できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let registrationError = hotKeyManager.registrationError {
                Text(registrationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Divider()
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
        let destination: TaskStatus = section == .active ? .active : .inbox
        if destination == .active { task.move(to: .active) }
        modelContext.insert(task)
        TaskOrdering.placeFirst(task, among: tasks.filter { $0.status == destination })
        if save() { newTitle = "" }
    }

    private func move(_ task: TaskItem, to destination: TaskStatus) {
        let destinationTasks = tasks.filter { $0.status == destination }
        task.move(to: destination)
        TaskOrdering.placeFirst(task, among: destinationTasks)
        save()
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
        launchStatus = SMAppService.mainApp.status
    }

    private func startRecordingShortcut() {
        guard !recordingShortcut else { return }
        recordingShortcut = true
        hotKeyManager.suspend()
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecordingShortcut()
            } else if let candidate = GlobalShortcut(event: event) {
                do {
                    try hotKeyManager.update(candidate)
                    shortcut = candidate
                } catch {
                    errorMessage = error.localizedDescription
                }
                stopRecordingShortcut()
            } else {
                errorMessage = "修飾キーを2つ以上と英数字を組み合わせてください。"
            }
            return nil
        }
    }

    private func stopRecordingShortcut() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
        if recordingShortcut {
            recordingShortcut = false
            hotKeyManager.resume()
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
