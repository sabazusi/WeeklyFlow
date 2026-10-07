import AppKit
import SwiftData
import SwiftUI

@main
struct WeeklyFlowApp: App {
    private let modelContainer: ModelContainer?
    private let startupError: String?

    init() {
        do {
            modelContainer = try ModelContainer(for: TaskItem.self)
            startupError = nil
        } catch {
            modelContainer = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        MenuBarExtra("WeeklyFlow", systemImage: "checkmark.circle") {
            if let modelContainer {
                MainView()
                    .modelContainer(modelContainer)
                    .frame(width: 780, height: 560)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("タスクデータを開けませんでした")
                        .font(.headline)
                    Text(startupError ?? "不明なエラー")
                        .foregroundStyle(.secondary)
                    Button("終了") { NSApp.terminate(nil) }
                }
                .padding(20)
                .frame(width: 380)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
