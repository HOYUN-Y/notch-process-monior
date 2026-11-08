import ApplicationServices
import XCTest
@testable import MenuBarKit

final class LogicTests: XCTestCase {
    private func entry(pid: pid_t = 1, index: Int = 0, siblings: Int = 1, app: String = "App", name: String? = nil,
                       actions: [String] = ["AXPress"], bundleURL: URL? = nil) -> MenuBarEntry {
        MenuBarEntry(pid: pid, index: index, siblingCount: siblings, appName: app, bundleID: nil, bundleURL: bundleURL,
                     name: name, frame: nil, actions: actions, overlapsNotch: false,
                     element: AXUIElementCreateSystemWide())
    }

    func testDisplayNameDistinguishesUnnamedSiblings() {
        XCTAssertEqual(entry(name: "Wi-Fi").displayName, "Wi-Fi")
        XCTAssertEqual(entry().displayName, "이름 없는 항목")
        XCTAssertEqual(entry(index: 2, siblings: 3).displayName, "이름 없는 항목 3")
        XCTAssertNotEqual(entry(pid: 1, index: 0).id, entry(pid: 1, index: 1).id)
    }

    func testMenuActionPrefersPressAndNilWhenUnsupported() {
        XCTAssertEqual(entry(actions: ["AXShowMenu", "AXPress"]).menuAction, "AXPress")
        XCTAssertEqual(entry(actions: ["AXShowMenu"]).menuAction, "AXShowMenu")
        XCTAssertNil(entry(actions: ["AXCancel"]).menuAction)
    }

    func testFilterMatchesAppAndItemNameIgnoringCase() {
        let all = [entry(app: "Syncthing", name: "Status"), entry(pid: 2, app: "Control Center", name: "Wi-Fi")]
        XCTAssertEqual(filtered(all, query: "  wifi ").count, 0)
        XCTAssertEqual(filtered(all, query: "wi-fi").map(\.appName), ["Control Center"])
        XCTAssertEqual(filtered(all, query: "SYNC").map(\.appName), ["Syncthing"])
        XCTAssertEqual(filtered(all, query: " ").count, 2)
    }

    func testOwnerAppURLOnlyForTopLevelNonSystemApps() {
        XCTAssertNotNil(MenuBarEntry.ownerAppURL(URL(fileURLWithPath: "/Applications/Foo.app")))
        XCTAssertNil(MenuBarEntry.ownerAppURL(URL(fileURLWithPath: "/System/Library/CoreServices/ControlCenter.app")))
        XCTAssertNil(MenuBarEntry.ownerAppURL(URL(fileURLWithPath: "/Applications/Foo.app/Contents/Library/LoginItems/Helper.app")))
        XCTAssertNil(MenuBarEntry.ownerAppURL(URL(fileURLWithPath: "/Applications/Foo.app/Contents/XPCServices/Helper.xpc")))
        XCTAssertNil(MenuBarEntry.ownerAppURL(URL(fileURLWithPath: "/usr/local/bin/tool")))
        XCTAssertNil(MenuBarEntry.ownerAppURL(nil))
    }

    func testClassifyDistinguishesTimeoutFromImmediateRefusal() {
        XCTAssertEqual(classify(.cannotComplete, elapsed: 1.0, timeout: 1.0), .noResponse)
        XCTAssertEqual(classify(.cannotComplete, elapsed: 0.01, timeout: 1.0), .unreachable)
        XCTAssertEqual(classify(.apiDisabled, elapsed: 0, timeout: 1), .permissionLost)
        XCTAssertEqual(classify(.noValue, elapsed: 0, timeout: 1), .noValue)
        XCTAssertEqual(classify(.actionUnsupported, elapsed: 0, timeout: 1), .unsupported)
    }

    func testNotchRectConvertsToAccessibilityCoordinates() {
        // 1800x1169 화면, 위쪽 38pt 중 790..1010이 노치
        let r = notchRect(screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169), primaryHeight: 1169,
                          left: CGRect(x: 0, y: 1131, width: 790, height: 38),
                          right: CGRect(x: 1010, y: 1131, width: 790, height: 38), topInset: 38)
        XCTAssertEqual(r, CGRect(x: 790, y: 0, width: 220, height: 38))
        XCTAssertTrue(r.intersects(CGRect(x: 1007, y: 7, width: 24, height: 24)))
        XCTAssertFalse(r.intersects(CGRect(x: 1032, y: 7, width: 24, height: 24)))
    }

    func testQuitRequestIsNotTerminationUntilObserved() {
        XCTAssertEqual(quitState(accepted: true, terminated: false, waited: 1), .requested)
        XCTAssertEqual(quitState(accepted: true, terminated: false, waited: 10), .stillRunning)
        XCTAssertEqual(quitState(accepted: true, terminated: true, waited: 1), .terminated)
        XCTAssertEqual(quitState(accepted: false, terminated: false, waited: 0), .notAccepted)
    }

    func testPermissionCheckMessageShowsTimeAndResult() {
        XCTAssertEqual(permissionCheckMessage(trusted: nil, time: ""), "아직 확인하지 않았습니다.")
        let denied = permissionCheckMessage(trusted: false, time: "12:00:01")
        XCTAssertTrue(denied.contains("12:00:01") && denied.contains("아직 이 앱을 허용하지 않았습니다"))
        XCTAssertNotEqual(denied, permissionCheckMessage(trusted: false, time: "12:00:02"))
        XCTAssertTrue(permissionCheckMessage(trusted: true, time: "12:00:03").contains("허용되었습니다"))
    }

    func testGroupFailuresCountsSameAppAndReasonWithoutDropping() {
        let failures = [AXScanner.Failure(appName: "Safari Web Content", reason: "응답 없음"),
                        AXScanner.Failure(appName: "Safari Web Content", reason: "응답 없음"),
                        AXScanner.Failure(appName: "Safari Web Content", reason: "조회 실패"),
                        AXScanner.Failure(appName: "Foo", reason: "응답 없음")]
        let groups = groupFailures(failures)
        XCTAssertEqual(groups.map(\.count), [2, 1, 1])
        XCTAssertEqual(groups.map(\.reason), ["응답 없음", "조회 실패", "응답 없음"])
        XCTAssertEqual(groups.reduce(0) { $0 + $1.count }, failures.count)
        XCTAssertTrue(groupFailures([]).isEmpty)
    }
}
