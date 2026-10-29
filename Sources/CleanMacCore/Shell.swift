import Foundation
import Darwin

/// 외부 명령을 실행하고 표준 출력을 문자열로 반환한다.
@discardableResult
public func shell(_ launchPath: String, _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        return ""
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

/// C API(sysctlbyname)로 문자열 값을 빠르게 조회하고 실패 시 외부 명령으로 폴백한다.
public func sysctl(_ name: String) -> String {
    if let val = sysctlString(name), !val.isEmpty {
        return val
    }
    return shell("/usr/sbin/sysctl", ["-n", name]).trimmingCharacters(in: .whitespacesAndNewlines)
}

public func sysctlString(_ name: String) -> String? {
    var size: Int = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
}

public func sysctlInt64(_ name: String) -> Int64? {
    var value: Int64 = 0
    var size = MemoryLayout<Int64>.size
    if sysctlbyname(name, &value, &size, nil, 0) == 0 {
        if size == MemoryLayout<Int32>.size {
            var val32: Int32 = 0
            var size32 = MemoryLayout<Int32>.size
            if sysctlbyname(name, &val32, &size32, nil, 0) == 0 {
                return Int64(val32)
            }
        }
        return value
    }
    var val32: Int32 = 0
    var size32 = MemoryLayout<Int32>.size
    if sysctlbyname(name, &val32, &size32, nil, 0) == 0 {
        return Int64(val32)
    }
    return nil
}

/// 지정한 PID의 프로세스에 종료 시그널(기본 SIGTERM)을 보낸다.
@discardableResult
public func terminateProcess(pid: Int32, force: Bool = false) -> Bool {
    guard pid > 1 else { return false }
    let sig = force ? SIGKILL : SIGTERM
    return Darwin.kill(pid, sig) == 0
}
