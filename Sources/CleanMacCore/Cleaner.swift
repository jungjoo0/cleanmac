import Foundation

public struct CleanTarget: Identifiable, Sendable, Hashable {
    public var id: String { url.path }
    public let name: String
    public let url: URL
    public let note: String
    public let excludedURLs: Set<URL>
    public var size: Int64

    public init(name: String, url: URL, note: String, excludedURLs: Set<URL> = [], size: Int64 = 0) {
        self.name = name
        self.url = url
        self.note = note
        self.excludedURLs = excludedURLs
        self.size = size
    }
}

public struct LargeFileItem: Identifiable, Sendable, Hashable {
    public var id: String { url.path }
    public let name: String
    public let url: URL
    public let size: Int64
    public let modifiedDate: Date?

    public init(name: String, url: URL, size: Int64, modifiedDate: Date?) {
        self.name = name
        self.url = url
        self.size = size
        self.modifiedDate = modifiedDate
    }
}

/// 존재하는 정리 대상만 크기를 병렬로 계산해 큰 순서로 반환한다.
/// ~/Library/Caches 하위에서 개별 항목으로 분리된 캐시는 '사용자 앱 캐시'에서 제외하여 중복 계산과 의도치 않은 삭제를 방지한다.
/// 휴지통은 TCC 보호로 직접 접근이 불가해 여기서 다루지 않는다 — trashItemCount()/emptyTrash() 사용.
public func scanCleanTargets() -> [CleanTarget] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let cachesDir = home.appendingPathComponent("Library/Caches")

    let specificCacheSubdirs: [(name: String, subpath: String, note: String)] = [
        ("SwiftPM 캐시", "org.swift.swiftpm", "Swift Package Manager 패키지 캐시"),
        ("Homebrew 캐시", "Homebrew", "brew 다운로드 캐시"),
        ("CocoaPods 캐시", "CocoaPods", "CocoaPods 다운로드 캐시"),
        ("pip 캐시", "pip", "Python pip 패키지 캐시"),
        ("Yarn 캐시", "Yarn", "Yarn 패키지 다운로드 캐시"),
        ("pnpm 캐시", "pnpm", "pnpm 패키지 캐시"),
        ("Go 빌드 캐시", "go-build", "Go 컴파일 캐시"),
    ]

    let excludedFromGeneralCaches = Set(specificCacheSubdirs.map { cachesDir.appendingPathComponent($0.subpath) })

    var candidates: [CleanTarget] = [
        CleanTarget(
            name: "사용자 앱 캐시",
            url: cachesDir,
            note: "앱이 다시 만들 수 있는 임시 데이터 (개별 분류 캐시 제외)",
            excludedURLs: excludedFromGeneralCaches
        ),
        CleanTarget(
            name: "사용자 로그",
            url: home.appendingPathComponent("Library/Logs"),
            note: "오래된 앱 진단/실행 로그 파일"
        ),
        CleanTarget(
            name: "Xcode DerivedData",
            url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            note: "Xcode 빌드 산출물 및 인덱스 (다시 빌드하면 복원)"
        ),
        CleanTarget(
            name: "Xcode iOS DeviceSupport",
            url: home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"),
            note: "연결했던 iOS 기기 심볼 데이터 (기기 재연결 시 복원)"
        ),
        CleanTarget(
            name: "Xcode 시뮬레이터 캐시",
            url: home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"),
            note: "iOS/watchOS 시뮬레이터 임시 캐시"
        ),
        CleanTarget(
            name: "npm 캐시",
            url: home.appendingPathComponent(".npm/_cacache"),
            note: "npm 패키지 다운로드 캐시"
        ),
        CleanTarget(
            name: "Gradle 캐시",
            url: home.appendingPathComponent(".gradle/caches"),
            note: "Java/Android Gradle 빌드 캐시"
        ),
        CleanTarget(
            name: "Cargo 캐시",
            url: home.appendingPathComponent(".cargo/registry/cache"),
            note: "Rust Cargo 크레이트 다운로드 캐시"
        ),
    ]

    for item in specificCacheSubdirs {
        candidates.append(
            CleanTarget(
                name: item.name,
                url: cachesDir.appendingPathComponent(item.subpath),
                note: item.note
            )
        )
    }

    let fm = FileManager.default
    let existing = candidates.filter { target in
        var isDirectory: ObjCBool = false
        return fm.fileExists(atPath: target.url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    guard !existing.isEmpty else { return [] }

    let lock = NSLock()
    var results: [CleanTarget] = []
    results.reserveCapacity(existing.count)

    DispatchQueue.concurrentPerform(iterations: existing.count) { index in
        var target = existing[index]
        target.size = directorySize(at: target.url, excluding: target.excludedURLs)
        lock.lock()
        results.append(target)
        lock.unlock()
    }

    return results.sorted { $0.size > $1.size }
}

/// ~/Library/Caches 안에서 가장 큰 하위 폴더를 병렬로 계산해 반환한다.
public func topCacheSubdirectories(limit: Int = 5) -> [(name: String, size: Int64)] {
    let cachesURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches")
    guard let subdirs = try? FileManager.default.contentsOfDirectory(
        at: cachesURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
    ) else { return [] }

    let lock = NSLock()
    var entries: [(name: String, size: Int64)] = []
    entries.reserveCapacity(subdirs.count)

    DispatchQueue.concurrentPerform(iterations: subdirs.count) { index in
        let url = subdirs[index]
        let size = directorySize(at: url)
        guard size > 0 else { return }
        lock.lock()
        entries.append((name: url.lastPathComponent, size: size))
        lock.unlock()
    }

    return entries
        .sorted { $0.size > $1.size }
        .prefix(limit)
        .map { $0 }
}

/// 지정한 폴더(기본: ~/Downloads)에서 일정 크기 이상인 대용량 파일/번들을 크기순으로 반환한다.
public func scanLargeFiles(
    in directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
    minSizeBytes: Int64 = 50 * 1024 * 1024,
    limit: Int = 15
) -> [LargeFileItem] {
    let fm = FileManager.default
    let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isPackageKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey
    ]
    guard let items = try? fm.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var results: [LargeFileItem] = []
    for url in items {
        let values = try? url.resourceValues(forKeys: keys)
        let size: Int64
        if values?.isDirectory == true {
            size = directorySize(at: url)
        } else {
            size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        guard size >= minSizeBytes else { continue }
        results.append(
            LargeFileItem(
                name: url.lastPathComponent,
                url: url,
                size: size,
                modifiedDate: values?.contentModificationDate
            )
        )
    }

    return results
        .sorted { $0.size > $1.size }
        .prefix(limit)
        .map { $0 }
}

/// 선택한 대용량 파일을 휴지통으로 이동한다.
@discardableResult
public func moveItemToTrash(_ url: URL) -> Bool {
    do {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        return true
    } catch {
        return false
    }
}

/// 휴지통의 항목 수. macOS가 ~/.Trash 직접 접근을 막으므로(TCC) Finder에 물어본다.
/// 자동화 권한이 없거나 거부되면 nil.
public func trashItemCount() -> Int? {
    let output = shell("/usr/bin/osascript", ["-e", "tell application \"Finder\" to count items in trash"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return Int(output)
}

/// Finder를 통해 휴지통을 비운다. 비워졌는지 확인해 성공 여부를 반환한다.
@discardableResult
public func emptyTrash() -> Bool {
    shell("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"])
    return trashItemCount() == 0
}

/// 대상 디렉터리의 내용물을 삭제한다. 디렉터리 자체와 제외 경로(excludedURLs)는 남긴다.
/// 사용 중이거나 보호된 항목은 건너뛴다.
public func removeContents(of targets: [CleanTarget]) -> (freed: Int64, skipped: Int) {
    let fm = FileManager.default
    var freed: Int64 = 0
    var skipped = 0
    for target in targets {
        let normalizedExclusions = Set(target.excludedURLs.map { $0.standardizedFileURL.path })
        let contents = (try? fm.contentsOfDirectory(at: target.url, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            if normalizedExclusions.contains(item.standardizedFileURL.path) {
                continue
            }
            let itemSize = directorySize(at: item)
            do {
                try fm.removeItem(at: item)
                freed += itemSize
            } catch {
                skipped += 1
            }
        }
    }
    return (freed, skipped)
}
