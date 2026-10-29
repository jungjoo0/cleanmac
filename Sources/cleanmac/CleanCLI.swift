import Foundation
import CleanMacCore

struct CleanOptions {
    var dryRun = false
    var skipConfirm = false
    var includeTrash = false
    var interactive = false
    var onlyKeywords: [String] = []
    var excludeKeywords: [String] = []
}

func runClean(options: CleanOptions) {
    print(ANSI.bold("🧹 cleanmac 캐시 정리"))
    print(ANSI.dim("크기를 계산하는 중입니다… (병렬 스캔 진행 중)"))

    var targets = scanCleanTargets()

    if !options.onlyKeywords.isEmpty {
        targets = targets.filter { target in
            options.onlyKeywords.contains { kw in
                target.name.localizedCaseInsensitiveContains(kw) || target.url.path.localizedCaseInsensitiveContains(kw)
            }
        }
    }
    if !options.excludeKeywords.isEmpty {
        targets = targets.filter { target in
            !options.excludeKeywords.contains { kw in
                target.name.localizedCaseInsensitiveContains(kw) || target.url.path.localizedCaseInsensitiveContains(kw)
            }
        }
    }

    printSection("정리 대상")
    var totalSize: Int64 = 0
    for (idx, target) in targets.enumerated() {
        totalSize += target.size
        let num = String(format: "[%2d]", idx + 1)
        let name = target.name.padding(toLength: 24, withPad: " ", startingAt: 0)
        let size = formatBytes(target.size).padding(toLength: 12, withPad: " ", startingAt: 0)
        print("  \(ANSI.dim(num)) \(name) \(ANSI.bold(size)) \(ANSI.dim(target.note))")
    }
    if options.includeTrash {
        let name = "휴지통".padding(toLength: 24, withPad: " ", startingAt: 0)
        let count = trashItemCount().map { "\($0)개 항목" } ?? "권한 필요"
        print("  \(ANSI.dim("[ T]")) \(name) \(ANSI.bold(count.padding(toLength: 12, withPad: " ", startingAt: 0))) \(ANSI.dim("Finder로 비움 (복구 불가)"))")
    }
    print("")
    print("  합계: \(ANSI.bold(ANSI.green(formatBytes(totalSize))))")

    let topSubdirs = topCacheSubdirectories(limit: 5)
    if !topSubdirs.isEmpty {
        printSection("가장 큰 캐시 폴더 Top 5")
        for entry in topSubdirs {
            let size = formatBytes(entry.size).padding(toLength: 12, withPad: " ", startingAt: 0)
            print("  \(size) \(entry.name)")
        }
    }

    if options.dryRun {
        print("")
        print(ANSI.yellow("(dry-run) 실제로 삭제하지 않았습니다. 삭제하려면 --dry-run 없이 실행하세요."))
        return
    }

    guard !targets.isEmpty || options.includeTrash else {
        print(ANSI.yellow("정리할 대상이 없습니다."))
        return
    }

    var selectedTargets = targets
    if options.interactive {
        guard let picked = promptSelectTargets(targets) else {
            print("취소했습니다.")
            return
        }
        selectedTargets = picked
    } else if !options.skipConfirm {
        print("")
        print("위 항목의 \(ANSI.bold("내용물"))을 삭제합니다. 앱 실행 중 캐시는 자동으로 건너뜁니다.")
        print("계속할까요? [y(전체 삭제)/s(번호로 선택)/N(취소)] ", terminator: "")
        let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if answer == "s" || answer == "select" {
            guard let picked = promptSelectTargets(targets) else {
                print("취소했습니다.")
                return
            }
            selectedTargets = picked
        } else if answer != "y" && answer != "yes" {
            print("취소했습니다.")
            return
        }
    }

    printSection("삭제 진행")
    var freed: Int64 = 0
    var skipped = 0
    for target in selectedTargets {
        let result = removeContents(of: [target])
        freed += result.freed
        skipped += result.skipped
        print("  \(ANSI.green("✓")) \(target.name): \(formatBytes(result.freed)) 확보")
    }
    if options.includeTrash {
        if emptyTrash() {
            print("  \(ANSI.green("✓")) 휴지통 비움")
        } else {
            print("  \(ANSI.yellow("⚠")) 휴지통을 비우지 못했습니다. Finder 자동화 권한을 허용해 주세요.")
        }
    }

    print("")
    print(ANSI.bold(ANSI.green("✨ 총 \(formatBytes(freed)) 를 확보했습니다.")))
    if skipped > 0 {
        print(ANSI.dim("(\(skipped)개 항목은 사용 중이거나 보호되어 있어 건너뛰었습니다)"))
    }
}

private func promptSelectTargets(_ targets: [CleanTarget]) -> [CleanTarget]? {
    print("삭제할 항목 번호를 쉼표로 구분해 입력하세요 (예: 1,3,4 / 전체: all / 취소: q): ", terminator: "")
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
        return nil
    }
    if input.lowercased() == "q" || input.lowercased() == "n" {
        return nil
    }
    if input.lowercased() == "all" || input.lowercased() == "a" {
        return targets
    }
    let indices = input
        .split(whereSeparator: { $0 == "," || $0 == " " })
        .compactMap { Int($0) }
        .filter { $0 >= 1 && $0 <= targets.count }
    guard !indices.isEmpty else { return nil }
    var seen = Set<Int>()
    var chosen: [CleanTarget] = []
    for idx in indices where !seen.contains(idx) {
        seen.insert(idx)
        chosen.append(targets[idx - 1])
    }
    return chosen
}

func runLargeFiles(minMB: Int64 = 50, interactive: Bool = false) {
    print(ANSI.bold("📦 cleanmac 다운로드 폴더 대용량 파일 탐색 (\(minMB)MB 이상)"))
    let items = scanLargeFiles(minSizeBytes: minMB * 1024 * 1024, limit: 20)
    guard !items.isEmpty else {
        print(ANSI.green("✓ ~/Downloads 에 \(minMB)MB 이상인 대용량 항목이 없습니다."))
        return
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    printSection("~/Downloads 대용량 항목")
    var total: Int64 = 0
    for (idx, item) in items.enumerated() {
        total += item.size
        let num = String(format: "[%2d]", idx + 1)
        let size = formatBytes(item.size).padding(toLength: 12, withPad: " ", startingAt: 0)
        let dateStr = item.modifiedDate.map { dateFormatter.string(from: $0) } ?? "----"
        print("  \(ANSI.dim(num)) \(ANSI.bold(size)) \(ANSI.dim(dateStr))  \(item.name)")
    }
    print("")
    print("  합계: \(ANSI.bold(ANSI.green(formatBytes(total))))")

    guard interactive else {
        print(ANSI.dim("  💡 대화형으로 휴지통에 이동하려면 'cleanmac large -i' 로 실행하세요."))
        return
    }

    print("")
    print("휴지통으로 이동할 번호를 입력하세요 (예: 1,2 / 취소: 엔터): ", terminator: "")
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
        print("취소했습니다.")
        return
    }
    let indices = input
        .split(whereSeparator: { $0 == "," || $0 == " " })
        .compactMap { Int($0) }
        .filter { $0 >= 1 && $0 <= items.count }
    guard !indices.isEmpty else {
        print("선택된 항목이 없습니다.")
        return
    }

    var freed: Int64 = 0
    for idx in Set(indices).sorted() {
        let item = items[idx - 1]
        if moveItemToTrash(item.url) {
            freed += item.size
            print("  \(ANSI.green("✓")) 휴지통 이동 완료: \(item.name) (\(formatBytes(item.size)))")
        } else {
            print("  \(ANSI.yellow("⚠")) 이동 실패: \(item.name)")
        }
    }
    print(ANSI.bold(ANSI.green("✨ 총 \(formatBytes(freed)) 항목을 휴지통으로 이동했습니다.")))
}
