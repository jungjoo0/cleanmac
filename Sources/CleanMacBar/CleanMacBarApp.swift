import SwiftUI
import CleanMacCore

@main
struct CleanMacBarApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Dock에 나타나지 않는 메뉴바 전용 앱
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("CleanMac", systemImage: "sparkles") {
            ContentView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var report: SystemReport?
    @Published var refreshing = false
    @Published var targets: [CleanTarget]?
    @Published var scanning = false
    @Published var cleaning = false
    @Published var resultMessage: String?

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        report = await Task.detached(priority: .userInitiated) {
            collectSystemReport()
        }.value
        refreshing = false
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        resultMessage = nil
        Task {
            targets = await Task.detached(priority: .userInitiated) {
                scanCleanTargets()
            }.value
            scanning = false
        }
    }

    func clean() {
        guard let targets, !cleaning else { return }
        cleaning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                removeContents(of: targets)
            }.value
            var message = "✨ \(formatBytes(result.freed)) 확보했습니다."
            if result.skipped > 0 {
                message += " (\(result.skipped)개 항목은 사용 중이라 건너뜀)"
            }
            resultMessage = message
            self.targets = nil
            cleaning = false
        }
    }
}
