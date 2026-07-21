import Foundation

public struct CleanTarget: Identifiable, Sendable {
    public var id: String { url.path }
    public let name: String
    public let url: URL
    public let note: String
    public var size: Int64

    public init(name: String, url: URL, note: String, size: Int64 = 0) {
        self.name = name
        self.url = url
        self.note = note
        self.size = size
    }
}

/// 존재하는 정리 대상만 크기를 계산해 큰 순서로 반환한다.
/// 휴지통은 TCC 보호로 직접 접근이 불가해 여기서 다루지 않는다 — trashItemCount()/emptyTrash() 사용.
public func scanCleanTargets() -> [CleanTarget] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidates = [
        CleanTarget(name: "사용자 앱 캐시", url: home.appendingPathComponent("Library/Caches"),
                    note: "앱이 다시 만들 수 있는 임시 데이터"),
        CleanTarget(name: "사용자 로그", url: home.appendingPathComponent("Library/Logs"),
                    note: "오래된 앱 로그 파일"),
        CleanTarget(name: "npm 캐시", url: home.appendingPathComponent(".npm/_cacache"),
                    note: "npm 패키지 다운로드 캐시"),
        CleanTarget(name: "Xcode DerivedData", url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                    note: "Xcode 빌드 산출물 (다시 빌드하면 복원)"),
        CleanTarget(name: "CocoaPods 캐시", url: home.appendingPathComponent("Library/Caches/CocoaPods"),
                    note: "CocoaPods 다운로드 캐시"),
        CleanTarget(name: "Homebrew 캐시", url: home.appendingPathComponent("Library/Caches/Homebrew"),
                    note: "brew 다운로드 캐시"),
        CleanTarget(name: "pip 캐시", url: home.appendingPathComponent("Library/Caches/pip"),
                    note: "pip 패키지 다운로드 캐시"),
    ]
    let fm = FileManager.default
    var targets: [CleanTarget] = []
    for var target in candidates {
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: target.url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { continue }
        target.size = directorySize(at: target.url)
        targets.append(target)
    }
    return targets.sorted { $0.size > $1.size }
}

/// ~/Library/Caches 안에서 가장 큰 하위 폴더를 반환한다.
public func topCacheSubdirectories(limit: Int = 5) -> [(name: String, size: Int64)] {
    let cachesURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches")
    guard let subdirs = try? FileManager.default.contentsOfDirectory(
        at: cachesURL, includingPropertiesForKeys: nil) else { return [] }
    return subdirs
        .map { (name: $0.lastPathComponent, size: directorySize(at: $0)) }
        .sorted { $0.size > $1.size }
        .prefix(limit)
        .map { $0 }
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

/// 대상 디렉터리의 내용물을 삭제한다. 디렉터리 자체는 남긴다.
/// 사용 중이거나 보호된 항목은 건너뛴다.
public func removeContents(of targets: [CleanTarget]) -> (freed: Int64, skipped: Int) {
    let fm = FileManager.default
    var freed: Int64 = 0
    var skipped = 0
    for target in targets {
        let contents = (try? fm.contentsOfDirectory(at: target.url, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
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
