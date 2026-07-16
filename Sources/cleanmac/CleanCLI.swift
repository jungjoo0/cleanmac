import Foundation
import CleanMacCore

struct CleanOptions {
    var dryRun = false
    var skipConfirm = false
    var includeTrash = false
}

func runClean(options: CleanOptions) {
    print(ANSI.bold("🧹 cleanmac 캐시 정리"))
    print(ANSI.dim("크기를 계산하는 중입니다… (캐시가 많으면 시간이 걸릴 수 있습니다)"))

    let targets = scanCleanTargets(includeTrash: options.includeTrash)

    printSection("정리 대상")
    var totalSize: Int64 = 0
    for target in targets {
        totalSize += target.size
        let name = target.name.padding(toLength: 22, withPad: " ", startingAt: 0)
        let size = formatBytes(target.size).padding(toLength: 12, withPad: " ", startingAt: 0)
        print("  \(name) \(ANSI.bold(size)) \(ANSI.dim(target.note))")
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

    if !options.skipConfirm {
        print("")
        print("위 항목의 \(ANSI.bold("내용물"))을 삭제합니다. 앱 실행 중 캐시는 자동으로 건너뜁니다.")
        print("계속할까요? [y/N] ", terminator: "")
        let answer = readLine()?.lowercased() ?? ""
        guard answer == "y" || answer == "yes" else {
            print("취소했습니다.")
            return
        }
    }

    printSection("삭제 진행")
    var freed: Int64 = 0
    var skipped = 0
    for target in targets {
        let result = removeContents(of: [target])
        freed += result.freed
        skipped += result.skipped
        print("  \(ANSI.green("✓")) \(target.name): \(formatBytes(result.freed)) 확보")
    }

    print("")
    print(ANSI.bold(ANSI.green("✨ 총 \(formatBytes(freed)) 를 확보했습니다.")))
    if skipped > 0 {
        print(ANSI.dim("(\(skipped)개 항목은 사용 중이거나 보호되어 있어 건너뛰었습니다)"))
    }
}
