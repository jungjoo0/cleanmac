import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

func printHelp() {
    print("""
    cleanmac — 맥이 느려진 원인을 진단하고 캐시를 정리하는 도구

    사용법:
      cleanmac diagnose          시스템 상태 진단 (기본 명령)
      cleanmac clean             캐시/임시 파일 크기를 보여주고 확인 후 삭제
      cleanmac clean --dry-run   삭제하지 않고 크기만 확인
      cleanmac clean --yes       확인 없이 바로 삭제
      cleanmac clean --trash     휴지통 비우기도 포함
      cleanmac help              이 도움말 표시
    """)
}

switch arguments.first {
case nil, "diagnose":
    runDiagnose()
case "clean":
    var options = CleanOptions()
    for flag in arguments.dropFirst() {
        switch flag {
        case "--dry-run": options.dryRun = true
        case "--yes", "-y": options.skipConfirm = true
        case "--trash": options.includeTrash = true
        default:
            print(ANSI.red("알 수 없는 옵션: \(flag)"))
            printHelp()
            exit(1)
        }
    }
    runClean(options: options)
case "help", "--help", "-h":
    printHelp()
default:
    print(ANSI.red("알 수 없는 명령: \(arguments.first!)"))
    printHelp()
    exit(1)
}
