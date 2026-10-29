import Foundation
import CleanMacCore

private func makeBar(ratio: Double, width: Int = 20, alert: Bool = false) -> String {
    let clamped = min(max(ratio, 0), 1)
    let filled = Int((clamped * Double(width)).rounded())
    let empty = max(width - filled, 0)
    let barText = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    if alert {
        return "[\(ANSI.yellow(barText))]"
    }
    return "[\(ANSI.green(barText))]"
}

func runDiagnose() {
    print(ANSI.bold("🩺 cleanmac 시스템 진단"))
    let report = collectSystemReport()

    printSection("시스템 정보")
    print("macOS \(report.osVersion)  ·  \(report.model)")
    if let uptime = report.uptime {
        let days = Int(uptime) / 86400
        let hours = (Int(uptime) % 86400) / 3600
        print("가동 시간: \(days)일 \(hours)시간")
    }

    printSection("CPU")
    if report.loadAverages.count >= 3 {
        let l = report.loadAverages
        let busy = l[0] > Double(report.coreCount)
        let bar = makeBar(ratio: report.cpuLoadRatio, alert: busy)
        print("\(bar) 로드 평균 (1/5/15분): \(l[0]) / \(l[1]) / \(l[2])  ·  코어 \(report.coreCount)개")
    }
    print(ANSI.dim("CPU 사용량 상위 프로세스:"))
    for process in report.topCPU {
        let pidStr = String(format: "PID %-6d", process.pid)
        print("  \(String(format: "%5.1f%%", process.cpuPercent))  \(ANSI.dim(pidStr))  \(process.name)")
    }

    printSection("메모리")
    let memAlert = report.memoryPressureLevel > 1 || report.memoryUsageRatio > 0.85
    let memBar = makeBar(ratio: report.memoryUsageRatio, alert: memAlert)
    let memPct = Int((report.memoryUsageRatio * 100).rounded())
    print("\(memBar) \(formatBytes(report.usedMemory)) / \(formatBytes(report.totalMemory)) (\(memPct)%)")
    print("상세: 앱 \(formatBytes(report.activeMemory)) · 고정 \(formatBytes(report.wiredMemory)) · 압축 \(formatBytes(report.compressedMemory))")
    print("스왑: \(formatBytes(report.swapUsed)) 사용 / \(formatBytes(report.swapTotal))")
    print(ANSI.dim("메모리 사용량 상위 프로세스:"))
    for process in report.topMemory {
        let size = formatBytes(process.memoryBytes).padding(toLength: 10, withPad: " ", startingAt: 0)
        let pidStr = String(format: "PID %-6d", process.pid)
        print("  \(size)  \(ANSI.dim(pidStr))  \(process.name)")
    }

    printSection("디스크")
    if report.diskTotal > 0 {
        let percentFree = Double(report.diskAvailable) / Double(report.diskTotal) * 100
        let diskAlert = percentFree < 10
        let diskBar = makeBar(ratio: report.diskUsageRatio, alert: diskAlert)
        print("\(diskBar) 여유 공간: \(formatBytes(report.diskAvailable)) / \(formatBytes(report.diskTotal))  (여유 \(String(format: "%.1f", percentFree))%)")
    }

    printSection("로그인 시작 항목")
    for group in report.launchItems {
        print("\(group.label): \(group.items.count)개")
        for item in group.items.prefix(10) {
            print(ANSI.dim("  · \(item)"))
        }
        if group.items.count > 10 {
            print(ANSI.dim("  · … 외 \(group.items.count - 10)개"))
        }
    }

    printSection("진단 요약")
    if report.warnings.isEmpty {
        print(ANSI.green("✓ 특별한 문제를 발견하지 못했습니다. 시스템이 정상 범위입니다."))
    } else {
        for warning in report.warnings {
            print(ANSI.yellow("⚠ ") + warning)
        }
    }
    print("")
}
