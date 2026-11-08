import SwiftUI

@main
struct MenuBarGatherApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        // WindowGroup: 창을 닫은 뒤 Dock 아이콘을 누르면 창이 다시 열린다. 상태 막대 아이콘은 만들지 않는다.
        WindowGroup("메뉴 막대 모아보기") {
            ContentView(store: store)
        }
        .defaultSize(width: 900, height: 640)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
