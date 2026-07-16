import Foundation

/// 터미널일 때만 ANSI 색상을 사용한다.
enum ANSI {
    static let enabled = isatty(STDOUT_FILENO) == 1

    static func wrap(_ text: String, _ code: String) -> String {
        enabled ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }

    static func bold(_ t: String) -> String { wrap(t, "1") }
    static func dim(_ t: String) -> String { wrap(t, "2") }
    static func red(_ t: String) -> String { wrap(t, "31") }
    static func green(_ t: String) -> String { wrap(t, "32") }
    static func yellow(_ t: String) -> String { wrap(t, "33") }
    static func cyan(_ t: String) -> String { wrap(t, "36") }
}

func printSection(_ title: String) {
    print("")
    print(ANSI.bold(ANSI.cyan("── \(title) " + String(repeating: "─", count: max(2, 44 - title.count)))))
}
