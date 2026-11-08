import AppKit
import MenuBarKit

enum Permission { case granted, notGranted, revoked }

enum RowStatus: Equatable {
    case requesting, sent, noResponse
    /// macOS가 결과를 확인해 주지 않았다. 요청이 실행됐을 수 있다.
    case unconfirmed(Int32)
    case failed(String)

    /// 실행 여부가 불확실해 새로고침 전에는 다시 보내지 않는다.
    var isUncertain: Bool {
        switch self {
        case .noResponse, .unconfirmed: return true
        default: return false
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var permission: Permission = .notGranted
    /// 가장 최근 권한 확인(시각, 결과). 미허용 화면에서 "다시 확인"의 결과를 보여 준다.
    @Published private(set) var lastCheck: (date: Date, trusted: Bool)?
    @Published private(set) var entries: [MenuBarEntry] = []
    @Published private(set) var failures: [AXScanner.Failure] = []
    @Published private(set) var scannedApps = 0
    @Published private(set) var isScanning = false
    @Published private(set) var hasScanned = false
    @Published private(set) var rowStatus: [String: RowStatus] = [:]
    @Published private(set) var requestInFlight = false
    /// pid별 앱 종료 요청 상태. 요청 수락과 실제 종료를 구분한다.
    @Published private(set) var quitStates: [pid_t: QuitState] = [:]
    private var everGranted = false
    private var lastScan = Date.distantPast

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // 메뉴가 닫히며 앱이 다시 활성화되는 경우를 위해 2초 안에는 다시 조회하지 않는다.
            MainActor.assumeIsolated { if let self, Date().timeIntervalSince(self.lastScan) > 2 { self.refresh(keepStatus: true) } }
        }
        refresh()
    }

    /// 활성화로 인한 자동 갱신은 직전 실행 결과 표시를 지우지 않는다. 직접 새로고침할 때만 지운다.
    func refresh(keepStatus: Bool = false) {
        guard !isScanning, !requestInFlight else { return }
        guard updatePermission() else { return }
        isScanning = true
        if !keepStatus { rowStatus = [:] }
        Task.detached(priority: .userInitiated) {
            let result = AXScanner.scan()
            await MainActor.run { self.finish(result) }
        }
    }

    /// 사용자가 누른 경우에만 시스템 권한 요청 창을 띄운다. 설정은 자동으로 바꾸지 않는다.
    func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// 실행 중인 번들을 Finder에서 선택해 보여 준다. 설정의 + 버튼으로 정확한 앱을 추가하게 하기 위함.
    func revealBundle() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openMenu(_ entry: MenuBarEntry) {
        guard !requestInFlight, !isScanning, rowStatus[entry.id]?.isUncertain != true, updatePermission() else { return }
        requestInFlight = true
        rowStatus[entry.id] = .requesting
        Task.detached(priority: .userInitiated) {
            let outcome = AXScanner.openMenu(entry)
            await MainActor.run { self.finish(entry, outcome) }
        }
    }

    func openApp(_ entry: MenuBarEntry) {
        guard let url = entry.ownerAppURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error { Task { @MainActor in self.rowStatus[entry.id] = .failed("앱을 열지 못했습니다: \(error.localizedDescription)") } }
        }
    }

    /// 정상 종료 요청(terminate)만 보낸다. 강제 종료나 재요청은 하지 않으며, 저장 확인은 대상 앱이 처리한다.
    func requestQuit(_ entry: MenuBarEntry) {
        let pid = entry.pid
        guard entry.ownerAppURL != nil, !isScanning, quitStates[pid] != .requested,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.bundleURL == entry.bundleURL else { return }
        let accepted = app.terminate()
        let start = Date()
        quitStates[pid] = quitState(accepted: accepted, terminated: false, waited: 0)
        Task {
            var state = quitStates[pid]!
            while state == .requested {
                try? await Task.sleep(for: .milliseconds(500))
                state = quitState(accepted: accepted, terminated: app.isTerminated, waited: Date().timeIntervalSince(start))
                quitStates[pid] = state
            }
            if state == .terminated {
                quitStates[pid] = nil
                entries.removeAll { $0.pid == pid }
                refresh(keepStatus: true)
            }
        }
    }

    // MARK: - 내부

    @discardableResult
    private func updatePermission() -> Bool {
        let trusted = AXScanner.isTrusted
        lastCheck = (Date(), trusted)
        if trusted {
            everGranted = true
            permission = .granted
            return true
        }
        permission = everGranted ? .revoked : .notGranted
        entries = []; failures = []; hasScanned = false
        return false
    }

    private func finish(_ result: AXScanner.Result) {
        isScanning = false
        lastScan = Date()
        // 조회 도중 권한이 사라졌다면 빈 목록이나 불완전한 목록을 결과로 반영하지 않는다.
        let trusted = updatePermission()
        guard !result.permissionLost, trusted else { return }
        // 조회 중 종료된 앱의 항목이 이전 결과로 다시 표시되지 않게 생존을 확인한다.
        entries = result.entries.filter { NSRunningApplication(processIdentifier: $0.pid)?.isTerminated == false }
        failures = result.failures
        scannedApps = result.scannedApps
        hasScanned = true
    }

    private func finish(_ entry: MenuBarEntry, _ outcome: Outcome) {
        requestInFlight = false
        switch outcome {
        case .ok: rowStatus[entry.id] = .sent
        case .noResponse: rowStatus[entry.id] = .noResponse
        case .permissionLost: updatePermission()
        case .unsupported: rowStatus[entry.id] = .failed("이 항목은 메뉴 열기를 지원하지 않습니다.")
        case .invalidElement: rowStatus[entry.id] = .failed("항목이 사라졌거나 바뀌었습니다. 새로고침하세요.")
        case .failed(let code): rowStatus[entry.id] = .unconfirmed(code)
        default: rowStatus[entry.id] = .unconfirmed(0)
        }
    }
}
