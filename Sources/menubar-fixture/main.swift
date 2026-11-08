import AppKit

// 검증용 상태 항목 N개(기본 2, 인자로 지정). 각 항목은 NSMenu 하나를 연다. 종료하면 사라진다.
let count = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 2
guard (1...20).contains(count) else {
    FileHandle.standardError.write(Data("usage: menubar-fixture [1-20]\n".utf8))
    exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let menu = NSMenu()
menu.addItem(withTitle: "검증용 메뉴 항목", action: nil, keyEquivalent: "")
let items = (0..<count).map { i -> NSStatusItem in
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "F\(i)"
    item.button?.setAccessibilityLabel("검증용 항목 \(i)")
    item.menu = menu
    return item
}
_ = items
app.run()
