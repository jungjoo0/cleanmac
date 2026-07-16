import Foundation
import CleanMacCore

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
        print("로드 평균 (1/5/15분): \(l[0]) / \(l[1]) / \(l[2])  ·  코어 \(report.coreCount)개")
    }
    print(ANSI.dim("CPU 사용량 상위 프로세스:"))
    for process in report.topCPU {
        print("  \(String(format: "%5.1f%%", process.cpuPercent))  \(process.name)")
    }

    printSection("메모리")
    print("물리 메모리: \(formatBytes(report.totalMemory))")
    print("사용 중: \(formatBytes(report.usedMemory))  (앱 \(formatBytes(report.activeMemory)) · 고정 \(formatBytes(report.wiredMemory)) · 압축 \(formatBytes(report.compressedMemory)))")
    print("스왑: \(formatBytes(report.swapUsed)) 사용 / \(formatBytes(report.swapTotal))")
    print(ANSI.dim("메모리 사용량 상위 프로세스:"))
    for process in report.topMemory {
        let size = formatBytes(process.memoryBytes).padding(toLength: 10, withPad: " ", startingAt: 0)
        print("  \(size)  \(process.name)")
    }

    printSection("디스크")
    if report.diskTotal > 0 {
        let percentFree = Double(report.diskAvailable) / Double(report.diskTotal) * 100
        print("여유 공간: \(formatBytes(report.diskAvailable)) / \(formatBytes(report.diskTotal))  (\(String(format: "%.1f", percentFree))%)")
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
