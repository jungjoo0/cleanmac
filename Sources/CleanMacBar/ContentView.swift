import SwiftUI
import CleanMacCore

private enum MenuTab: String, CaseIterable, Identifiable {
    case overview = "상태 · 정리"
    case processes = "프로세스"
    case largeFiles = "대용량 파일"

    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("showMenuBarSummary") private var showMenuBarSummary = true
    @AppStorage("autoRefresh") private var autoRefresh = true
    @State private var selectedTab: MenuTab = .overview
    @State private var confirmClean = false
    @State private var processSortByMemory = false

    private let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Picker("", selection: $selectedTab) {
                ForEach(MenuTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let message = model.resultMessage {
                HStack(spacing: 6) {
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        model.resultMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(6)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            switch selectedTab {
            case .overview:
                overviewTab
            case .processes:
                processesTab
            case .largeFiles:
                largeFilesTab
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
        .task { await model.refresh() }
        .onReceive(refreshTimer) { _ in
            guard autoRefresh else { return }
            Task { await model.refresh() }
        }
    }

    // MARK: - 상단 헤더

    private var header: some View {
        HStack(spacing: 6) {
            Label("CleanMac", systemImage: "sparkles")
                .font(.headline)
            if let uptime = model.report?.uptime {
                let days = Int(uptime) / 86400
                let hours = (Int(uptime) % 86400) / 3600
                Text("· \(days)일 \(hours)시간")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Toggle("메뉴바에 메모리 % 표시", isOn: $showMenuBarSummary)
                Toggle("10초마다 자동 새로고침", isOn: $autoRefresh)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .help("표시 및 자동 새로고침 설정")

            Button {
                Task { await model.refresh() }
            } label: {
                if model.refreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("지금 다시 점검")
        }
    }

    // MARK: - 탭 1: 상태 및 캐시 정리

    @ViewBuilder
    private var overviewTab: some View {
        if let report = model.report {
            statsView(report)
            if !report.warnings.isEmpty {
                warningsView(report.warnings)
            }
        } else {
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Text("시스템 점검 중…").foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)
        }

        Divider()
        cleanSection
    }

    private func statsView(_ report: SystemReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let load = report.loadAverages.first {
                let busy = load > Double(report.coreCount)
                statGaugeRow(
                    icon: "cpu",
                    label: "CPU 로드",
                    value: String(format: "%.2f / %d코어", load, report.coreCount),
                    ratio: report.cpuLoadRatio,
                    alert: busy
                )
            }
            let memPct = Int((report.memoryUsageRatio * 100).rounded())
            statGaugeRow(
                icon: "memorychip",
                label: "메모리",
                value: "\(formatBytes(report.usedMemory)) / \(formatBytes(report.totalMemory)) (\(memPct)%)",
                ratio: report.memoryUsageRatio,
                alert: report.memoryPressureLevel > 1 || report.memoryUsageRatio > 0.85
            )
            if report.swapTotal > 0 || report.swapUsed > 0 {
                let swapRatio = report.swapTotal > 0 ? min(Double(report.swapUsed) / Double(report.swapTotal), 1.0) : 0
                statGaugeRow(
                    icon: "arrow.left.arrow.right",
                    label: "스왑",
                    value: "\(formatBytes(report.swapUsed)) 사용",
                    ratio: swapRatio,
                    alert: report.swapUsed > 2 * 1024 * 1024 * 1024
                )
            }
            if report.diskTotal > 0 {
                let percentFree = Double(report.diskAvailable) / Double(report.diskTotal) * 100
                statGaugeRow(
                    icon: "internaldrive",
                    label: "디스크 여유",
                    value: "\(formatBytes(report.diskAvailable)) (\(String(format: "%.0f", percentFree))%)",
                    ratio: report.diskUsageRatio,
                    alert: percentFree < 10
                )
            }
        }
    }

    private func statGaugeRow(icon: String, label: String, value: String, ratio: Double, alert: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(alert ? .orange : .secondary)
                Text(label)
                Spacer()
                Text(value)
                    .foregroundStyle(alert ? .orange : .secondary)
                    .fontWeight(alert ? .semibold : .regular)
            }
            .font(.system(size: 12))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(alert ? Color.orange : Color.accentColor)
                        .frame(width: max(geo.size.width * min(max(ratio, 0), 1), 2))
                }
            }
            .frame(height: 4)
        }
    }

    private func warningsView(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 10))
                        .padding(.top, 2)
                    Text(warning)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(8)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 캐시 정리 섹션

    @ViewBuilder
    private var cleanSection: some View {
        HStack {
            Toggle("휴지통 비우기 포함 (복구 불가)", isOn: $model.includeTrash)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .disabled(model.scanning || model.cleaning)
            Spacer()
            if model.targets != nil {
                Button("재스캔") {
                    confirmClean = false
                    model.scan()
                }
                .controlSize(.mini)
                .disabled(model.scanning || model.cleaning)
            }
        }

        if let targets = model.targets {
            HStack {
                Text("정리할 항목 선택")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                let allSelected = !model.selectedTargetIDs.isEmpty && model.selectedTargetIDs.count == targets.filter { $0.size > 0 }.count
                Button(allSelected ? "전체 해제" : "전체 선택") {
                    model.setAllSelected(!allSelected)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(targets) { target in
                        HStack(spacing: 6) {
                            Toggle(isOn: Binding(
                                get: { model.selectedTargetIDs.contains(target.id) },
                                set: { _ in model.toggleSelection(for: target) }
                            )) {
                                Text(target.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(target.size == 0)

                            Spacer()

                            Text(formatBytes(target.size))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Button {
                                model.revealInFinder(target.url)
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("\(target.url.path) Finder에서 열기")
                        }
                    }
                    if model.includeTrash {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text("휴지통")
                                .font(.system(size: 12))
                            Spacer()
                            Text(model.trashCount.map { "\($0)개 항목" } ?? "권한 필요")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 160)

            Divider()
            HStack {
                Text("선택 합계 (\(model.selectedTargets.count)개)")
                    .fontWeight(.semibold)
                Spacer()
                Text(formatBytes(model.selectedTotalSize))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 12))

            if model.cleaning {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("정리 중…").font(.system(size: 12))
                    Spacer()
                }
            } else if confirmClean {
                VStack(alignment: .leading, spacing: 8) {
                    Text("선택한 \(model.selectedTargets.count)개 항목의 내용물을 삭제합니다. 사용 중인 파일은 자동으로 건너뜁니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("취소") { confirmClean = false }
                            .frame(maxWidth: .infinity)
                        Button("삭제 확인") {
                            confirmClean = false
                            model.clean()
                        }
                        .frame(maxWidth: .infinity)
                        .tint(.red)
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Button {
                    confirmClean = true
                } label: {
                    Text("선택 항목 정리하기 (\(formatBytes(model.selectedTotalSize)))")
                        .frame(maxWidth: .infinity)
                }
                .tint(.red)
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedTargets.isEmpty && !model.includeTrash)
            }
        } else {
            Button {
                model.scan()
            } label: {
                if model.scanning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("캐시 크기 병렬 계산 중…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("캐시 스캔", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(model.scanning)
        }
    }

    // MARK: - 탭 2: 상위 프로세스 관리

    @ViewBuilder
    private var processesTab: some View {
        HStack {
            Text(processSortByMemory ? "메모리 상위 프로세스" : "CPU 상위 프로세스")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Picker("", selection: $processSortByMemory) {
                Text("CPU순").tag(false)
                Text("메모리순").tag(true)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 130)
        }

        if let report = model.report {
            let list = processSortByMemory ? report.topMemory : report.topCPU
            if list.isEmpty {
                Text("프로세스 정보가 없습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(list) { proc in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(proc.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Text("PID \(proc.pid)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(String(format: "%.1f%%", proc.cpuPercent))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(proc.cpuPercent > 80 ? .orange : .secondary)
                                .frame(width: 52, alignment: .trailing)
                            Text(formatBytes(proc.memoryBytes))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 68, alignment: .trailing)
                            Button {
                                model.killProcess(proc)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("'\(proc.name)' (PID \(proc.pid)) 종료 (SIGTERM)")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    // MARK: - 탭 3: 대용량 다운로드 파일

    @ViewBuilder
    private var largeFilesTab: some View {
        HStack {
            Text("~/Downloads 대용량 항목 (50MB+)")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                model.scanDownloadsLargeFiles()
            } label: {
                Label("스캔", systemImage: "magnifyingglass")
            }
            .controlSize(.small)
            .disabled(model.scanningLargeFiles)
        }

        if model.scanningLargeFiles {
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Text("다운로드 폴더 스캔 중…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 12)
        } else if let items = model.largeFiles {
            if items.isEmpty {
                Text("✓ 50MB 이상인 대용량 파일이 없습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items) { item in
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    Text(formatBytes(item.size))
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    model.revealInFinder(item.url)
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.borderless)
                                .help("Finder에서 보기")

                                Button {
                                    model.trashLargeFile(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                                .help("휴지통으로 이동")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        } else {
            Text("스캔 버튼을 눌러 다운로드 폴더의 대용량 설치 파일이나 압축 파일을 정리하세요.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .onAppear {
                    model.scanDownloadsLargeFiles()
                }
        }
    }

    // MARK: - 하단 푸터

    private var footer: some View {
        HStack {
            Text("cleanmac")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
            .controlSize(.small)
        }
    }
}
