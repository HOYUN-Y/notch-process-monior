// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuBarGather",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MenuBarKit"),
        .executableTarget(name: "MenuBarGather", dependencies: ["MenuBarKit"]),
        // 검증용 CLI: 조회 결과 출력, 지정한 항목에 액션 1회 요청
        .executableTarget(name: "menubar-dump", dependencies: ["MenuBarKit"]),
        .executableTarget(name: "menubar-fixture"),
        .testTarget(name: "MenuBarKitTests", dependencies: ["MenuBarKit"]),
    ]
)
