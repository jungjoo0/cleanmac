import SwiftUI
import AppKit
import CleanMacCore

@main
struct CleanMacBarApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("showMenuBarSummary") private var showMenuBarSummary = true

    init() {
        // Dock에 나타나지 않는 메뉴바 전용 앱
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: (model.report?.warnings.isEmpty == false) ? "sparkles.tv.fill" : "sparkles")
                if showMenuBarSummary, let report = model.report, report.totalMemory > 0 {
                    let memPct = Int((report.memoryUsageRatio * 100).rounded())
                    Text("\(memPct)%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var report: SystemReport?
    @Published var refreshing = false
    @Published var targets: [CleanTarget]?
    @Published var selectedTargetIDs: Set<String> = []
    @Published var scanning = false
    @Published var cleaning = false
    @Published var resultMessage: String?
    @Published var trashCount: Int?
    @Published var includeTrash = false {
        didSet {
            if targets != nil { scan() }
        }
    }

    @Published var largeFiles: [LargeFileItem]?
    @Published var scanningLargeFiles = false

    var selectedTargets: [CleanTarget] {
        guard let targets else { return [] }
        return targets.filter { selectedTargetIDs.contains($0.id) }
    }

    var selectedTotalSize: Int64 {
        selectedTargets.reduce(0) { $0 + $1.size }
    }

    func toggleSelection(for target: CleanTarget) {
        if selectedTargetIDs.contains(target.id) {
            selectedTargetIDs.remove(target.id)
        } else {
            selectedTargetIDs.insert(target.id)
        }
    }

    func setAllSelected(_ selectAll: Bool) {
        guard let targets else { return }
        if selectAll {
            selectedTargetIDs = Set(targets.filter { $0.size > 0 }.map(\.id))
        } else {
            selectedTargetIDs.removeAll()
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

    func killProcess(_ sample: ProcessSample) {
        let pid = sample.pid
        let name = sample.name
        Task {
            let ok = await Task.detached(priority: .userInitiated) {
                terminateProcess(pid: pid)
            }.value
            if ok {
                resultMessage = "'\(name)' (PID \(pid)) 종료 신호를 보냈습니다."
            } else {
                resultMessage = "'\(name)' (PID \(pid)) 종료 권한이 없거나 이미 종료되었습니다."
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refresh()
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
            async let count = Task.detached(priority: .userInitiated) {
                includeTrash ? trashItemCount() : nil
            }.value
            let found = await scanned
            targets = found
            selectedTargetIDs = Set(found.filter { $0.size > 0 }.map(\.id))
            trashCount = await count
            scanning = false
        }
    }

    func clean() {
        let chosen = selectedTargets
        guard (!chosen.isEmpty || includeTrash), !cleaning else { return }
        let includeTrash = includeTrash
        cleaning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                removeContents(of: chosen)
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
            self.selectedTargetIDs.removeAll()
            self.trashCount = nil
            cleaning = false
            await refresh()
        }
    }

    func scanDownloadsLargeFiles() {
        guard !scanningLargeFiles else { return }
        scanningLargeFiles = true
        Task {
            largeFiles = await Task.detached(priority: .userInitiated) {
                scanLargeFiles(minSizeBytes: 50 * 1024 * 1024, limit: 15)
            }.value
            scanningLargeFiles = false
        }
    }

    func trashLargeFile(_ item: LargeFileItem) {
        if moveItemToTrash(item.url) {
            largeFiles?.removeAll { $0.id == item.id }
            resultMessage = "'\(item.name)' (\(formatBytes(item.size))) 항목을 휴지통으로 이동했습니다."
        } else {
            resultMessage = "'\(item.name)' 항목을 휴지통으로 이동하지 못했습니다."
        }
    }
}
