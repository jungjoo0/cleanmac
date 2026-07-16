import Foundation

public func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

/// 디렉터리 전체 크기(할당 기준)를 계산한다. 접근 불가 항목은 건너뛴다.
public func directorySize(at url: URL) -> Int64 {
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: Array(keys),
        options: [],
        errorHandler: { _, _ in true }
    ) else { return 0 }

    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
        guard let values = try? fileURL.resourceValues(forKeys: keys),
              values.isRegularFile == true else { continue }
        total += Int64(values.totalFileAllocatedSize ?? 0)
    }
    return total
}
