import AppKit
import ApplicationServices

public enum AXScanner {
    public static let scanTimeout: Float = 1.0
    public static let actionTimeout: Float = 2.0
    /// 앱 하나를 조회하는 데 쓸 수 있는 전체 시간. 개별 타임아웃이 쌓여 길어지는 것을 막는다.
    static let appBudget: TimeInterval = 3.0

    public struct Failure: Hashable, Sendable {
        public let appName: String
        public let reason: String
    }

    public struct Result: Sendable {
        public var entries: [MenuBarEntry] = []
        public var failures: [Failure] = []
        public var scannedApps = 0
        public var permissionLost = false
    }

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 요소별 타임아웃은 자식에 상속되지 않으므로, 이 프로세스 전체의 AX 호출 상한도 함께 둔다.
    private static let globalLimit: Void = {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), actionTimeout)
    }()

    /// 실행 중인 일반·보조(accessory) 앱의 AXExtrasMenuBar를 읽는다. 화면 좌표로 항목을 제외하지 않는다.
    /// prohibited 정책 프로세스(헬퍼 등)는 상태 항목을 가질 수 없어 건너뛴다.
    public static func scan() -> Result {
        _ = globalLimit
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy != .prohibited && $0.processIdentifier != me && !$0.isTerminated
        }
        let notches = currentNotchRects()
        let lock = NSLock()
        var result = Result(scannedApps: apps.count)
        DispatchQueue.concurrentPerform(iterations: apps.count) { i in
            let one = scan(app: apps[i], notches: notches)
            lock.lock()
            result.entries += one.entries
            result.failures += one.failures
            result.permissionLost = result.permissionLost || one.permissionLost
            lock.unlock()
        }
        result.entries.sort { ($0.appName, $0.frame == nil ? 1 : 0, $0.pid, $0.index) < ($1.appName, $1.frame == nil ? 1 : 0, $1.pid, $1.index) }
        result.failures.sort { $0.appName < $1.appName }
        return result
    }

    /// 메뉴 열기 요청을 정확히 한 번 보낸다. 응답이 늦어도 다시 보내지 않는다.
    public static func openMenu(_ entry: MenuBarEntry) -> Outcome {
        guard let action = entry.menuAction else { return .unsupported }
        _ = globalLimit
        AXUIElementSetMessagingTimeout(entry.element, actionTimeout)
        let start = Date()
        let err = AXUIElementPerformAction(entry.element, action as CFString)
        let outcome = classify(err, elapsed: Date().timeIntervalSince(start), timeout: actionTimeout)
        // 조회와 달리 실행에서 noValue는 정상 결과가 아니다.
        return outcome == .noValue ? .failed(err.rawValue) : outcome
    }

    // MARK: - 내부

    private static func currentNotchRects() -> [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        return NSScreen.screens.compactMap { s in
            guard s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea else { return nil }
            return notchRect(screenFrame: s.frame, primaryHeight: primary.frame.height, left: l, right: r, topInset: s.safeAreaInsets.top)
        }
    }

    private static func scan(app: NSRunningApplication, notches: [CGRect]) -> Result {
        let appName = app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)"
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, scanTimeout)
        let probe = Probe()

        var out = Result()
        let (bar, barOutcome) = probe.copy(root, kAXExtrasMenuBarAttribute)
        switch barOutcome {
        case .ok: break
        case .noValue, .unreachable: return out
        case .permissionLost: out.permissionLost = true; return out
        case .noResponse: out.failures = [Failure(appName: appName, reason: "응답 없음")]; return out
        default: out.failures = [Failure(appName: appName, reason: "조회 실패")]; return out
        }
        guard let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return out }
        let barElement = bar as! AXUIElement
        AXUIElementSetMessagingTimeout(barElement, scanTimeout)

        let children = probe.copy(barElement, kAXChildrenAttribute).0 as? [AXUIElement] ?? []
        for (i, el) in children.enumerated() where probe.active {
            AXUIElementSetMessagingTimeout(el, scanTimeout)
            let actions = probe.actionNames(el)
            let frame = probe.frame(of: el)
            let name = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute]
                .lazy.compactMap { probe.string(el, $0) }.first
            // 읽는 도중 중단됐다면 이름·액션이 불완전하므로 이 항목은 버린다.
            guard probe.active else { break }
            out.entries.append(MenuBarEntry(
                pid: app.processIdentifier, index: i, siblingCount: children.count,
                appName: appName, bundleID: app.bundleIdentifier, bundleURL: app.bundleURL,
                name: name, frame: frame, actions: actions,
                overlapsNotch: frame.map { f in notches.contains { $0.intersects(f) } } ?? false,
                element: el))
        }
        if probe.permissionLost {
            out.entries = []
            out.permissionLost = true
        } else if probe.stalled {
            out.failures = [Failure(appName: appName, reason: "응답 없음, 일부 항목 누락 가능")]
        }
        return out
    }
}

/// 앱 하나의 조회 상태. 첫 "응답 없음"이나 시간 예산 초과가 관찰되면 그 앱의 추가 조회를 멈춘다.
private final class Probe {
    private(set) var stalled = false
    private(set) var permissionLost = false
    private let deadline = Date().addingTimeInterval(AXScanner.appBudget)
    private var timeout: Float { AXScanner.scanTimeout }

    var active: Bool {
        if !stalled, !permissionLost, Date() >= deadline { stalled = true }
        return !stalled && !permissionLost
    }

    private func observe(_ err: AXError, since start: Date) -> Outcome {
        let outcome = classify(err, elapsed: Date().timeIntervalSince(start), timeout: timeout)
        if outcome == .noResponse { stalled = true }
        if outcome == .permissionLost { permissionLost = true }
        return outcome
    }

    func copy(_ el: AXUIElement, _ attr: String) -> (CFTypeRef?, Outcome) {
        guard active else { return (nil, permissionLost ? .permissionLost : .noResponse) }
        var value: CFTypeRef?
        let start = Date()
        let err = AXUIElementCopyAttributeValue(el, attr as CFString, &value)
        return (value, observe(err, since: start))
    }

    func actionNames(_ el: AXUIElement) -> [String] {
        guard active else { return [] }
        var names: CFArray?
        let start = Date()
        let err = AXUIElementCopyActionNames(el, &names)
        _ = observe(err, since: start)
        return names as? [String] ?? []
    }

    func string(_ el: AXUIElement, _ attr: String) -> String? {
        // 줄바꿈이 섞인 이름("이름\n상태")은 한 줄로 합친다.
        let s = (copy(el, attr).0 as? String)?.split(whereSeparator: \.isNewline).joined(separator: " · ")
            .trimmingCharacters(in: .whitespaces)
        return s?.isEmpty == false ? s : nil
    }

    func frame(of el: AXUIElement) -> CGRect? {
        var p = CGPoint.zero, s = CGSize.zero
        guard let pv = copy(el, kAXPositionAttribute).0, CFGetTypeID(pv) == AXValueGetTypeID(),
              let sv = copy(el, kAXSizeAttribute).0, CFGetTypeID(sv) == AXValueGetTypeID(),
              AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s),
              s.width > 0, s.height > 0 else { return nil }
        return CGRect(origin: p, size: s)
    }
}
