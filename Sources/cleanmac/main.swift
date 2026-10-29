import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

func printHelp() {
    print("""
    cleanmac — 맥이 느려진 원인을 진단하고 캐시를 정리하는 도구

    사용법:
      cleanmac diagnose                   시스템 상태 진단 (기본 명령)
      cleanmac clean                      캐시/임시 파일 크기를 보여주고 확인 후 삭제
      cleanmac clean --dry-run            삭제하지 않고 크기만 확인
      cleanmac clean --interactive (-i)   삭제할 캐시 항목을 번호로 선택
      cleanmac clean --only <키워드>      특정 키워드가 포함된 캐시만 대상에 포함
      cleanmac clean --exclude <키워드>   특정 키워드가 포함된 캐시는 제외
      cleanmac clean --yes (-y)           확인 없이 바로 삭제
      cleanmac clean --trash              휴지통 비우기도 포함
      cleanmac large [--min-mb <MB>] [-i] ~/Downloads 대용량 파일 탐색 및 휴지통 이동
      cleanmac help                       이 도움말 표시
    """)
}

switch arguments.first {
case nil, "diagnose":
    runDiagnose()
case "clean":
    var options = CleanOptions()
    var idx = 1
    while idx < arguments.count {
        let flag = arguments[idx]
        switch flag {
        case "--dry-run":
            options.dryRun = true
        case "--yes", "-y":
            options.skipConfirm = true
        case "--trash":
            options.includeTrash = true
        case "--interactive", "-i":
            options.interactive = true
        case "--only", "-o":
            idx += 1
            guard idx < arguments.count else {
                print(ANSI.red("--only 옵션에는 키워드가 필요합니다."))
                exit(1)
            }
            options.onlyKeywords.append(arguments[idx])
        case "--exclude", "-e":
            idx += 1
            guard idx < arguments.count else {
                print(ANSI.red("--exclude 옵션에는 키워드가 필요합니다."))
                exit(1)
            }
            options.excludeKeywords.append(arguments[idx])
        default:
            print(ANSI.red("알 수 없는 옵션: \(flag)"))
            printHelp()
            exit(1)
        }
        idx += 1
    }
    runClean(options: options)
case "large":
    var minMB: Int64 = 50
    var interactive = false
    var idx = 1
    while idx < arguments.count {
        let flag = arguments[idx]
        switch flag {
        case "--interactive", "-i":
            interactive = true
        case "--min-mb":
            idx += 1
            guard idx < arguments.count, let val = Int64(arguments[idx]), val > 0 else {
                print(ANSI.red("--min-mb 옵션에는 양의 정수가 필요합니다."))
                exit(1)
            }
            minMB = val
        default:
            print(ANSI.red("알 수 없는 옵션: \(flag)"))
            printHelp()
            exit(1)
        }
        idx += 1
    }
    runLargeFiles(minMB: minMB, interactive: interactive)
case "help", "--help", "-h":
    printHelp()
default:
    print(ANSI.red("알 수 없는 명령: \(arguments.first!)"))
    printHelp()
    exit(1)
}
