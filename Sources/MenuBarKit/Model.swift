import ApplicationServices
import CoreGraphics
import Foundation

/// 접근성 API가 알려 준 메뉴 막대 오른쪽 항목 하나.
public struct MenuBarEntry: Identifiable, @unchecked Sendable {
    public let pid: pid_t
    /// 소유 프로세스의 AXExtrasMenuBar 안에서의 순서
    public let index: Int
    public let siblingCount: Int
    public let appName: String
    public let bundleID: String?
    public let bundleURL: URL?
    /// title → description → help → identifier 중 처음 비어 있지 않은 값
    public let name: String?
    /// 정보 표시용. 항목을 걸러내는 데 쓰지 않는다. 크기가 0이면 nil.
    public let frame: CGRect?
    public let actions: [String]
    public let overlapsNotch: Bool
    public let element: AXUIElement

    public var id: String { "\(pid):\(index)" }

    public var displayName: String {
        name ?? (siblingCount > 1 ? "이름 없는 항목 \(index + 1)" : "이름 없는 항목")
    }

    /// 메뉴 열기에 쓸 지원 액션. 없으면 nil.
    public var menuAction: String? {
        [kAXPressAction, kAXShowMenuAction].first { actions.contains($0) }
    }

    public var ownerAppURL: URL? { Self.ownerAppURL(bundleURL) }

    /// 앱 열기·앱 종료 대상 판정. 시스템 서비스, 앱 번들 안쪽 보조 프로세스(.xpc 포함),
    /// 번들이 .app이 아닌 프로세스는 소유 앱을 확실히 알 수 없으므로 nil.
    public static func ownerAppURL(_ url: URL?) -> URL? {
        guard let url, url.pathExtension == "app", !url.path.hasPrefix("/System/"),
              url.pathComponents.filter({ $0.hasSuffix(".app") }).count == 1 else { return nil }
        return url
    }
}

public func filtered(_ entries: [MenuBarEntry], query: String) -> [MenuBarEntry] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return entries }
    return entries.filter { $0.appName.localizedStandardContains(q) || $0.displayName.localizedStandardContains(q) }
}

public enum Outcome: Equatable, Sendable {
    case ok
    /// 속성 없음 또는 미지원. 조회에서는 정상(해당 앱에 항목 없음).
    case noValue
    /// 시간 제한까지 응답 없음. 요청이 이미 처리됐을 수 있다.
    case noResponse
    /// 곧바로 거절됨(접근성을 지원하지 않는 프로세스 등)
    case unreachable
    case unsupported
    case permissionLost
    case invalidElement
    case failed(Int32)
}

public func classify(_ err: AXError, elapsed: TimeInterval, timeout: Float) -> Outcome {
    switch err {
    case .success: return .ok
    case .noValue, .attributeUnsupported: return .noValue
    case .actionUnsupported: return .unsupported
    case .apiDisabled: return .permissionLost
    case .invalidUIElement: return .invalidElement
    case .cannotComplete: return elapsed >= Double(timeout) * 0.9 ? .noResponse : .unreachable
    default: return .failed(err.rawValue)
    }
}

/// 노치가 차지하는 영역을 접근성 좌표계(주 화면 왼쪽 위가 원점)로 변환한다.
public func notchRect(screenFrame: CGRect, primaryHeight: CGFloat, left: CGRect, right: CGRect, topInset: CGFloat) -> CGRect {
    CGRect(x: left.maxX, y: primaryHeight - screenFrame.maxY, width: right.minX - left.maxX, height: topInset)
}

public enum QuitState: Equatable, Sendable {
    case notAccepted
    /// 종료 요청이 받아들여졌을 뿐, 실제 종료는 아직 관찰되지 않았다.
    case requested
    /// 제한 시간이 지나도 실행 중(저장 확인 대기 등). 다시 요청하지 않는다.
    case stillRunning
    case terminated
}

public func quitState(accepted: Bool, terminated: Bool, waited: TimeInterval, limit: TimeInterval = 10) -> QuitState {
    if terminated { return .terminated }
    if !accepted { return .notAccepted }
    return waited >= limit ? .stillRunning : .requested
}

/// 권한 확인 결과 문구. 시각을 넣어, 결과가 같아도 다시 확인했다는 것을 화면에서 알 수 있게 한다.
public func permissionCheckMessage(trusted: Bool?, time: String) -> String {
    switch trusted {
    case nil: return "아직 확인하지 않았습니다."
    case true?: return "\(time) 확인: 허용되었습니다."
    case false?: return "\(time) 확인: macOS가 아직 이 앱을 허용하지 않았습니다."
    }
}
