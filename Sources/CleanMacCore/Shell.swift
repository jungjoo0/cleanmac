import Foundation

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

public func sysctl(_ name: String) -> String {
    shell("/usr/sbin/sysctl", ["-n", name]).trimmingCharacters(in: .whitespacesAndNewlines)
}
