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
    @Published var trashCount: Int?
    @Published var includeTrash = false {
        didSet {
            // 이미 스캔한 상태에서 토글하면 목록을 다시 계산한다
            if targets != nil { scan() }
        }
    }

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
        let includeTrash = includeTrash
        Task {
            async let scanned = Task.detached(priority: .userInitiated) {
                scanCleanTargets()
            }.value
            // 휴지통은 TCC 보호로 직접 못 읽으므로 Finder에 항목 수를 물어본다
            async let count = Task.detached(priority: .userInitiated) {
                includeTrash ? trashItemCount() : nil
            }.value
            targets = await scanned
            trashCount = await count
            scanning = false
        }
    }

    func clean() {
        guard let targets, !cleaning else { return }
        let includeTrash = includeTrash
        cleaning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                removeContents(of: targets)
            }.value
            let trashEmptied = await Task.detached(priority: .userInitiated) {
                includeTrash ? emptyTrash() : false
            }.value
            var message = "✨ \(formatBytes(result.freed)) 확보했습니다."
            if trashEmptied {
                message += " 휴지통도 비웠습니다."
            } else if includeTrash {
                message += " (휴지통은 Finder 자동화 권한이 없어 비우지 못함)"
            }
            if result.skipped > 0 {
                message += " (\(result.skipped)개 항목은 사용 중이라 건너뜀)"
            }
            resultMessage = message
            self.targets = nil
            self.trashCount = nil
            cleaning = false
        }
    }
}
