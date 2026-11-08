import Foundation
import MenuBarKit

// 사용법: menubar-dump            → 조회 결과 출력(읽기 전용)
//         menubar-dump --press ID → 조회 후 ID(pid:index) 항목에 메뉴 열기를 정확히 1회 요청
print("trusted: \(AXScanner.isTrusted)")
guard AXScanner.isTrusted else { exit(2) }
let result = AXScanner.scan()
print("apps scanned: \(result.scannedApps), entries: \(result.entries.count), failures: \(result.failures.count)")
for e in result.entries {
    let f = e.frame.map { "x=\(Int($0.minX))..\(Int($0.maxX)) y=\(Int($0.minY))" } ?? "no-frame"
    print("\(e.id)\t\(e.appName)\t\(e.displayName)\t\(f)\tnotch=\(e.overlapsNotch)\tactions=\(e.actions)\topenApp=\(e.ownerAppURL != nil)")
}
for f in result.failures { print("FAIL \(f.appName): \(f.reason)") }

if let i = CommandLine.arguments.firstIndex(of: "--press"), i + 1 < CommandLine.arguments.count {
    let id = CommandLine.arguments[i + 1]
    guard let e = result.entries.first(where: { $0.id == id }) else { print("press: \(id) not found"); exit(1) }
    let start = Date()
    let outcome = AXScanner.openMenu(e)
    print("press \(id) \(e.appName) / \(e.displayName): \(outcome) in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
}
