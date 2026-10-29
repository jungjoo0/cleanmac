import Foundation

public func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

/// 디렉터리 전체 크기(할당 기준)를 계산한다. 접근 불가 항목이나 제외 경로는 건너뛴다.
public func directorySize(at url: URL, excluding excludedURLs: Set<URL> = []) -> Int64 {
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isDirectoryKey]
    let normalizedExclusions = Set(excludedURLs.map { $0.standardizedFileURL.path })

    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
    if !isDir.boolValue {
        let values = try? url.resourceValues(forKeys: keys)
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }

    guard let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: Array(keys),
        options: [],
        errorHandler: { _, _ in true }
    ) else { return 0 }

    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
        if !normalizedExclusions.isEmpty {
            let standardizedPath = fileURL.standardizedFileURL.path
            if normalizedExclusions.contains(standardizedPath) {
                enumerator.skipDescendants()
                continue
            }
        }
        guard let values = try? fileURL.resourceValues(forKeys: keys),
              values.isRegularFile == true else { continue }
        total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
    return total
}
