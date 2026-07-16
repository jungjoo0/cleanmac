import Foundation

public struct ProcessSample: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: Int64

    public init(name: String, cpuPercent: Double, memoryBytes: Int64) {
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct LaunchItemGroup: Sendable {
    public let label: String
    public let items: [String]

    public init(label: String, items: [String]) {
        self.label = label
        self.items = items
    }
}

public struct SystemReport: Sendable {
    public var osVersion = ""
    public var model = ""
    public var bootTime: Date?
    public var coreCount = 1
    public var loadAverages: [Double] = []
    public var totalMemory: Int64 = 0
    public var activeMemory: Int64 = 0
    public var wiredMemory: Int64 = 0
    public var compressedMemory: Int64 = 0
    public var swapTotal: Int64 = 0
    public var swapUsed: Int64 = 0
    public var memoryPressureLevel = 1  // 1: 정상, 2: 경고, 4: 심각
    public var diskTotal: Int64 = 0
    public var diskAvailable: Int64 = 0
    public var topCPU: [ProcessSample] = []
    public var topMemory: [ProcessSample] = []
    public var launchItems: [LaunchItemGroup] = []
    public var warnings: [String] = []

    public init() {}

    public var usedMemory: Int64 { activeMemory + wiredMemory + compressedMemory }

    public var uptime: TimeInterval? {
        bootTime.map { Date().timeIntervalSince($0) }
    }
}

public func collectSystemReport() -> SystemReport {
    var report = SystemReport()

    report.osVersion = shell("/usr/bin/sw_vers", ["-productVersion"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    report.model = sysctl("hw.model")
    report.bootTime = parseBootTime()
    report.coreCount = Int(sysctl("hw.ncpu")) ?? 1

    // "{ 1.23 1.45 1.60 }"
    report.loadAverages = sysctl("vm.loadavg")
        .replacingOccurrences(of: "{", with: "")
        .replacingOccurrences(of: "}", with: "")
        .split(separator: " ")
        .compactMap { Double($0) }

    report.totalMemory = Int64(sysctl("hw.memsize")) ?? 0
    if let vm = parseVMStat() {
        report.activeMemory = vm.active
        report.wiredMemory = vm.wired
        report.compressedMemory = vm.compressed
    }
    if let swap = parseSwapUsage() {
        report.swapTotal = swap.total
        report.swapUsed = swap.used
    }
    report.memoryPressureLevel = Int(sysctl("kern.memorystatus_vm_pressure_level")) ?? 1

    if let disk = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
        .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
    ]), let total = disk.volumeTotalCapacity,
       let available = disk.volumeAvailableCapacityForImportantUsage {
        report.diskTotal = Int64(total)
        report.diskAvailable = available
    }

    report.topCPU = topProcesses(sortFlag: "-r")
    report.topMemory = topProcesses(sortFlag: "-m")
    report.launchItems = collectLaunchItems()
    report.warnings = makeWarnings(for: report)
    return report
}

// MARK: - 경고 생성

private func makeWarnings(for report: SystemReport) -> [String] {
    var warnings: [String] = []

    if let uptime = report.uptime {
        let days = Int(uptime) / 86400
        if days >= 14 {
            warnings.append("재부팅한 지 \(days)일이 지났습니다. 오래 켜두면 메모리 누수가 쌓일 수 있으니 재부팅을 권장합니다.")
        }
    }

    if let load1 = report.loadAverages.first, load1 > Double(report.coreCount) {
        warnings.append("1분 로드 평균(\(load1))이 코어 수(\(report.coreCount))를 넘습니다. CPU가 과부하 상태입니다.")
    }
    for process in report.topCPU where process.cpuPercent > 80 {
        warnings.append("'\(process.name)' 프로세스가 CPU를 \(String(format: "%.0f", process.cpuPercent))% 사용 중입니다.")
    }

    if report.totalMemory > 0, report.compressedMemory > report.totalMemory / 5 {
        warnings.append("압축 메모리가 \(formatBytes(report.compressedMemory))로 큽니다. 메모리가 부족해 시스템이 압축으로 버티는 중입니다.")
    }
    if report.swapUsed > 2 * 1024 * 1024 * 1024 {
        warnings.append("스왑을 \(formatBytes(report.swapUsed)) 사용 중입니다. 메모리 부족이 체감 속도 저하의 주요 원인일 가능성이 높습니다.")
    }
    if report.memoryPressureLevel == 2 {
        warnings.append("시스템 메모리 압박 수준이 '경고' 단계입니다.")
    } else if report.memoryPressureLevel == 4 {
        warnings.append("시스템 메모리 압박 수준이 '심각' 단계입니다. 사용하지 않는 앱을 종료하세요.")
    }

    if report.diskTotal > 0 {
        let percentFree = Double(report.diskAvailable) / Double(report.diskTotal) * 100
        if percentFree < 10 || report.diskAvailable < 20 * 1024 * 1024 * 1024 {
            warnings.append("디스크 여유 공간이 부족합니다. macOS는 여유 공간이 적으면 스왑·캐시 처리로 전체가 느려집니다. 캐시 정리를 권장합니다.")
        }
    }

    let totalAgents = report.launchItems.reduce(0) { $0 + $1.items.count }
    if totalAgents > 20 {
        warnings.append("로그인 시 자동 실행 항목이 \(totalAgents)개로 많습니다. 쓰지 않는 앱의 항목은 제거를 검토하세요.")
    }
    return warnings
}

// MARK: - 수집 헬퍼

private func topProcesses(sortFlag: String, limit: Int = 5) -> [ProcessSample] {
    // pcpu(%), rss(KB), comm(명령 이름)
    let output = shell("/bin/ps", ["-Aceo", "pcpu,rss,comm", sortFlag])
    return output.split(separator: "\n").dropFirst().prefix(limit).compactMap { line in
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3,
              let cpu = Double(parts[0]),
              let rssKB = Int64(parts[1]) else { return nil }
        return ProcessSample(name: String(parts[2]), cpuPercent: cpu, memoryBytes: rssKB * 1024)
    }
}

private func collectLaunchItems() -> [LaunchItemGroup] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let agentDirs = [
        ("\(home)/Library/LaunchAgents", "사용자 LaunchAgents"),
        ("/Library/LaunchAgents", "시스템 LaunchAgents"),
        ("/Library/LaunchDaemons", "시스템 LaunchDaemons"),
    ]
    return agentDirs.map { path, label in
        let items = (try? FileManager.default.contentsOfDirectory(atPath: path))?
            .filter { $0.hasSuffix(".plist") } ?? []
        return LaunchItemGroup(label: label, items: items)
    }
}

private func parseBootTime() -> Date? {
    // "{ sec = 1720000000, usec = 0 } ..."
    let raw = sysctl("kern.boottime")
    guard let secRange = raw.range(of: "sec = "),
          let comma = raw[secRange.upperBound...].firstIndex(of: ",") else { return nil }
    guard let sec = TimeInterval(raw[secRange.upperBound..<comma]) else { return nil }
    return Date(timeIntervalSince1970: sec)
}

private struct VMStat {
    var active: Int64 = 0
    var wired: Int64 = 0
    var compressed: Int64 = 0
}

private func parseVMStat() -> VMStat? {
    let output = shell("/usr/bin/vm_stat", [])
    guard !output.isEmpty else { return nil }

    var pageSize: Int64 = 4096
    if let range = output.range(of: "page size of "),
       let end = output[range.upperBound...].firstIndex(of: " "),
       let parsed = Int64(output[range.upperBound..<end]) {
        pageSize = parsed
    }

    func pages(_ label: String) -> Int64 {
        guard let range = output.range(of: label) else { return 0 }
        let rest = output[range.upperBound...]
        let digits = rest.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        return Int64(digits) ?? 0
    }

    var stat = VMStat()
    stat.active = pages("Pages active:") * pageSize
    stat.wired = pages("Pages wired down:") * pageSize
    stat.compressed = pages("Pages occupied by compressor:") * pageSize
    return stat
}

private func parseSwapUsage() -> (total: Int64, used: Int64)? {
    // "total = 2048.00M  used = 1234.56M  free = 813.44M  (encrypted)"
    let raw = sysctl("vm.swapusage")
    func value(after label: String) -> Int64? {
        guard let range = raw.range(of: "\(label) = ") else { return nil }
        let rest = raw[range.upperBound...]
        let number = rest.prefix(while: { $0.isNumber || $0 == "." })
        guard let mb = Double(number) else { return nil }
        return Int64(mb * 1024 * 1024)
    }
    guard let total = value(after: "total"), let used = value(after: "used") else { return nil }
    return (total, used)
}
