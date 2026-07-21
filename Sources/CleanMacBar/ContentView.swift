import SwiftUI
import CleanMacCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmClean = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
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
            Divider()

            HStack {
                Text("cleanmac").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 340)
        .task { await model.refresh() }
    }

    // MARK: - 상단

    private var header: some View {
        HStack {
            Label("CleanMac", systemImage: "sparkles")
                .font(.headline)
            Spacer()
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
            .help("다시 점검")
        }
    }

    // MARK: - 시스템 상태

    private func statsView(_ report: SystemReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if report.loadAverages.count >= 1 {
                let load = report.loadAverages[0]
                let busy = load > Double(report.coreCount)
                statRow(icon: "cpu", label: "CPU 로드",
                        value: String(format: "%.2f / 코어 %d개", load, report.coreCount),
                        alert: busy)
            }
            statRow(icon: "memorychip", label: "메모리",
                    value: "\(formatBytes(report.usedMemory)) / \(formatBytes(report.totalMemory)) 사용",
                    alert: report.memoryPressureLevel > 1)
            statRow(icon: "arrow.left.arrow.right", label: "스왑",
                    value: "\(formatBytes(report.swapUsed)) 사용",
                    alert: report.swapUsed > 2 * 1024 * 1024 * 1024)
            if report.diskTotal > 0 {
                let percentFree = Double(report.diskAvailable) / Double(report.diskTotal) * 100
                statRow(icon: "internaldrive", label: "디스크 여유",
                        value: "\(formatBytes(report.diskAvailable)) (\(String(format: "%.0f", percentFree))%)",
                        alert: percentFree < 10)
            }
        }
    }

    private func statRow(icon: String, label: String, value: String, alert: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(alert ? .orange : .secondary)
                .fontWeight(alert ? .semibold : .regular)
        }
        .font(.system(size: 12))
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

    // MARK: - 캐시 정리

    @ViewBuilder
    private var cleanSection: some View {
        Toggle("휴지통 비우기 포함 (복구 불가)", isOn: $model.includeTrash)
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .disabled(model.scanning || model.cleaning)

        if let message = model.resultMessage {
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        }

        if let targets = model.targets {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(targets) { target in
                    HStack {
                        Text(target.name)
                        Spacer()
                        Text(formatBytes(target.size))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
                if model.includeTrash {
                    HStack {
                        Text("휴지통")
                        Spacer()
                        Text(model.trashCount.map { "\($0)개 항목" } ?? "권한 필요")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
                Divider()
                HStack {
                    Text("합계").fontWeight(.semibold)
                    Spacer()
                    Text(formatBytes(targets.reduce(0) { $0 + $1.size }))
                        .fontWeight(.semibold)
                }
                .font(.system(size: 12))
            }

            if model.cleaning {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("정리 중…").font(.system(size: 12))
                    Spacer()
                }
            } else if confirmClean {
                // 별도 alert 창은 메뉴바 팝업을 닫아버리므로 팝업 안에서 바로 확인한다.
                VStack(alignment: .leading, spacing: 8) {
                    Text("정리 대상 폴더의 내용물을 삭제합니다. 사용 중인 파일은 자동으로 건너뜁니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("취소") { confirmClean = false }
                            .frame(maxWidth: .infinity)
                        Button("삭제") {
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
                    Text("정리하기").frame(maxWidth: .infinity)
                }
                .tint(.red)
                .buttonStyle(.borderedProminent)
            }
        } else {
            Button {
                model.scan()
            } label: {
                if model.scanning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("캐시 크기 계산 중…")
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
}
