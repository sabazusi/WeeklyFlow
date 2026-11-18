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
    @State private var newURLText = ""
    @AppStorage("WeeklyFlow.submitWithShiftReturn") private var submitWithShiftReturn = false
    @State private var editingTask: TaskItem?
    @State private var errorMessage: String?
    @State private var currentDate = Date()
    @State private var launchStatus = SMAppService.mainApp.status
    @State private var shortcut: GlobalShortcut?
    @State private var recordingShortcut = false
    @State private var shortcutMonitor: Any?
    @State private var doubleShiftEnabled = false
    @State private var doubleShiftNeedsPermission = false
    @State private var pendingScrollTaskID: UUID?
    @State private var quickAddFocusRequest = 0
    @State private var quickAddClearRequest = 0

    private var quickAddURLIsInvalid: Bool {
        !newURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && TaskLink.url(from: newURLText) == nil
    }

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
            TaskEditor(task: task) { title, notes, urlString in
                task.title = title
                task.notes = notes
                task.urlString = urlString
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
            hotKeyManager.refreshDoubleShiftMonitoring()
            doubleShiftNeedsPermission = hotKeyManager.doubleShiftNeedsPermission
            focusActiveInput()
        }
        .onReceive(NotificationCenter.default.publisher(for: .weeklyFlowDidOpen)) { _ in
            focusActiveInput()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            currentDate = date
        }
        .onAppear {
            launchStatus = SMAppService.mainApp.status
            shortcut = hotKeyManager.shortcut
            doubleShiftEnabled = hotKeyManager.doubleShiftEnabled
            hotKeyManager.refreshDoubleShiftMonitoring()
            doubleShiftNeedsPermission = hotKeyManager.doubleShiftNeedsPermission
            focusActiveInput()
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
                    copyToPasteboard(WeeklyReport.copyText(for: weekTasks, now: currentDate))
                }
            }
        }
        .padding(20)
    }

    private var quickAdd: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                QuickAddTitleField(
                    text: $newTitle,
                    submitWithShiftReturn: submitWithShiftReturn,
                    focusRequest: quickAddFocusRequest,
                    clearRequest: quickAddClearRequest,
                    onSubmit: addTask
                )
                .frame(height: 54)
                QuickAddURLField(
                    text: $newURLText,
                    submitWithShiftReturn: submitWithShiftReturn,
                    clearRequest: quickAddClearRequest,
                    onSubmit: addTask
                )
                .frame(height: 26)
                if quickAddURLIsInvalid {
                    Text("httpまたはhttpsのURLを入力してください。")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Button("追加", action: addTask)
                .disabled(QuickAddInput.validatedDraft(title: newTitle, urlText: newURLText) == nil)
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
                ScrollViewReader { proxy in
                    List {
                        ForEach(visibleTasks) { task in
                            taskRow(task)
                                .id(task.id)
                        }
                        .onMove(perform: section == .inbox || section == .active ? reorderTasks : nil)
                    }
                    .listStyle(.plain)
                    .onAppear { scrollToAddedTask(using: proxy) }
                    .onChange(of: visibleTasks.map(\.id)) { _, _ in
                        scrollToAddedTask(using: proxy)
                    }
                    .onChange(of: pendingScrollTaskID) { _, _ in
                        scrollToAddedTask(using: proxy)
                    }
                }
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
                            HStack {
                                Text("\(WeeklyReport.weekLabel(for: group.interval)) · \(group.tasks.count)件")
                                Spacer()
                                Button("コピー", systemImage: "doc.on.doc") {
                                    copyToPasteboard(WeeklyReport.copyText(for: group))
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .help("この週の完了タスクをコピー")
                            }
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

    private func scrollToAddedTask(using proxy: ScrollViewProxy) {
        guard let taskID = pendingScrollTaskID,
              visibleTasks.first?.id == taskID else { return }
        DispatchQueue.main.async {
            guard pendingScrollTaskID == taskID else { return }
            proxy.scrollTo(taskID, anchor: .top)
            pendingScrollTaskID = nil
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
            if let url = task.urlString.flatMap(TaskLink.url) {
                Button {
                    openTaskURL(url)
                } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(.borderless)
                .help(url.absoluteString)
                .accessibilityLabel("URLを開く")
            }
            Button("編集", systemImage: "square.and.pencil") { editingTask = task }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 7)
    }

    private func openTaskURL(_ url: URL) {
        let workspace = NSWorkspace.shared
        if let webURL = URL(string: "https://example.com"),
           let browser = workspace.urlForApplication(toOpen: webURL) {
            workspace.open([url], withApplicationAt: browser, configuration: .init(), completionHandler: nil)
        } else {
            workspace.open(url)
        }
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
            Toggle("Shiftを2回押して開閉", isOn: Binding(
                get: { doubleShiftEnabled },
                set: setDoubleShiftEnabled
            ))
            if doubleShiftNeedsPermission {
                Text("ほかのアプリでも検出するには、システム設定の「プライバシーとセキュリティ」→「アクセシビリティ」でWeeklyFlowを許可してください。許可後、WeeklyFlowに戻ると有効になります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Toggle("Shift + Enterで送信", isOn: $submitWithShiftReturn)
            Text(submitWithShiftReturn
                 ? "タスク欄ではEnterで改行し、Shift + Enterで追加します。URL欄でもShift + Enterで追加します。"
                 : "タスク欄とURL欄のどちらでもEnterで追加します。タスク欄ではShift + Enterで改行できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("タスクはこのMac内に保存されます。パネルを閉じてもメニューバーから再表示できます。")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }

    private func addTask() {
        guard let draft = QuickAddInput.validatedDraft(title: newTitle, urlText: newURLText) else { return }
        let task = TaskItem(title: draft.title)
        task.urlString = draft.urlString
        let destination: TaskStatus = section == .active ? .active : .inbox
        if destination == .active { task.move(to: .active) }
        modelContext.insert(task)
        TaskOrdering.placeFirst(task, among: tasks.filter { $0.status == destination })
        if save() {
            newTitle = ""
            newURLText = ""
            quickAddClearRequest += 1
            pendingScrollTaskID = task.id
            quickAddFocusRequest += 1
        }
    }

    private func focusActiveInput() {
        section = .active
        DispatchQueue.main.async {
            quickAddFocusRequest += 1
        }
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

    private func setDoubleShiftEnabled(_ enabled: Bool) {
        hotKeyManager.setDoubleShiftEnabled(enabled)
        doubleShiftEnabled = enabled
        doubleShiftNeedsPermission = hotKeyManager.doubleShiftNeedsPermission
    }

    private func startRecordingShortcut() {
        guard !recordingShortcut else { return }
        recordingShortcut = true
        hotKeyManager.suspend()
        hotKeyManager.suspendDoubleShift()
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
            hotKeyManager.resumeDoubleShift()
        }
    }
}

private struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var urlText: String
    @State private var confirmingDelete = false
    let onSave: (String, String, String?) -> Bool
    let onDelete: () -> Bool

    init(task: TaskItem, onSave: @escaping (String, String, String?) -> Bool, onDelete: @escaping () -> Bool) {
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
        _urlText = State(initialValue: task.urlString ?? "")
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var enteredURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isURLInvalid: Bool {
        !enteredURL.isEmpty && TaskLink.url(from: enteredURL) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("タスクを編集").font(.title2.bold())
            TextField("タイトル", text: $title)
            Text("説明")
                .font(.subheadline)
            TextEditor(text: $notes)
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Text("URL")
                .font(.subheadline)
            TextField("https://example.com", text: $urlText)
                .textFieldStyle(.roundedBorder)
            if isURLInvalid {
                Text("httpまたはhttpsのURLを入力してください。")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("削除", role: .destructive) { confirmingDelete = true }
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("保存") {
                    if onSave(
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes,
                        TaskLink.url(from: enteredURL)?.absoluteString
                    ) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isURLInvalid)
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

enum QuickAddInput {
    struct Draft {
        let title: String
        let urlString: String?
    }

    static func shouldSubmit(modifiers: NSEvent.ModifierFlags, withShift: Bool) -> Bool {
        let relevant = modifiers.intersection([.shift, .command, .option, .control])
        return relevant == (withShift ? .shift : [])
    }

    static func validatedDraft(title: String, urlText: String) -> Draft? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty { return Draft(title: trimmedTitle, urlString: nil) }
        guard let url = TaskLink.url(from: trimmedURL) else { return nil }
        return Draft(title: trimmedTitle, urlString: url.absoluteString)
    }
}

private final class QuickAddTitleTextView: NSTextView {
    var submitWithShiftReturn = false
    var onSubmit: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        ("新しいタスク" as NSString).draw(
            at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                        y: textContainerInset.height),
            withAttributes: attributes
        )
    }

    override func keyDown(with event: NSEvent) {
        // Enter confirms a Japanese IME candidate before it can submit a task.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
            if modifiers.isEmpty || modifiers == .shift {
                if QuickAddInput.shouldSubmit(modifiers: modifiers, withShift: submitWithShiftReturn) {
                    if !event.isARepeat { onSubmit?() }
                } else {
                    insertNewline(nil)
                }
                return
            }
        }
        super.keyDown(with: event)
    }
}

private struct QuickAddTitleField: NSViewRepresentable {
    @Binding var text: String
    let submitWithShiftReturn: Bool
    let focusRequest: Int
    let clearRequest: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let editor = QuickAddTitleTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 54))
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isHorizontallyResizable = false
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.textContainerInset = NSSize(width: 5, height: 5)
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel("新しいタスク")
        editor.string = text
        scrollView.documentView = editor
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let editor = scrollView.documentView as? QuickAddTitleTextView else { return }
        context.coordinator.parent = self
        editor.submitWithShiftReturn = submitWithShiftReturn
        editor.onSubmit = onSubmit
        // Only a successful submission clears the editor. SwiftUI state updates
        // must never replace text that the IME is still composing.
        if context.coordinator.lastClearRequest != clearRequest {
            context.coordinator.lastClearRequest = clearRequest
            editor.string = text
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak editor] in
                guard let editor, let window = editor.window else { return }
                window.makeFirstResponder(editor)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickAddTitleField
        var lastFocusRequest: Int?
        var lastClearRequest: Int

        init(_ parent: QuickAddTitleField) {
            self.parent = parent
            lastClearRequest = parent.clearRequest
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

private struct QuickAddURLField: NSViewRepresentable {
    @Binding var text: String
    let submitWithShiftReturn: Bool
    let clearRequest: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "URL（任意）"
        field.delegate = context.coordinator
        field.setAccessibilityLabel("URL")
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastClearRequest != clearRequest {
            context.coordinator.lastClearRequest = clearRequest
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickAddURLField
        var lastClearRequest: Int

        init(_ parent: QuickAddURLField) {
            self.parent = parent
            lastClearRequest = parent.clearRequest
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if textView.hasMarkedText() { return false }
            guard let event = NSApp.currentEvent, event.keyCode == 36 || event.keyCode == 76 else {
                return false
            }
            if QuickAddInput.shouldSubmit(modifiers: event.modifierFlags, withShift: parent.submitWithShiftReturn),
               !event.isARepeat {
                parent.onSubmit()
            }
            return true
        }
    }
}
