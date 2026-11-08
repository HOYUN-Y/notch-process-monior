import AppKit
import MenuBarKit
import SwiftUI

/// 목록과 하단 내용의 최대 폭. 넓은 창에서 항목 이름과 동작이 멀어지지 않게 가운데 열로 모은다.
private let contentWidth: CGFloat = 760

struct ContentView: View {
    @ObservedObject var store: Store
    @State private var query = ""
    @State private var selection: String?
    @State private var hovered: String?
    @State private var quitTarget: MenuBarEntry?
    @State private var showFailures = false

    var body: some View {
        Group {
            if store.permission == .granted { listScreen } else { PermissionView(store: store) }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        // 내용이 툴바 아래로 지나가지 않는 화면에서도 툴바가 시스템 회색이 아닌 같은 배경색을 쓰게 한다.
        .toolbarBackground(Theme.background, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .confirmationDialog("앱 종료 요청", isPresented: Binding(get: { quitTarget != nil }, set: { if !$0 { quitTarget = nil } }), presenting: quitTarget) { entry in
            Button("종료 요청 보내기", role: .destructive) { store.requestQuit(entry) }
            Button("취소", role: .cancel) {}
        } message: { entry in
            Text("\(entry.appName) (PID \(String(entry.pid)))에 정상 종료를 요청합니다. 저장 확인 등은 해당 앱이 처리하며, 강제 종료하지 않습니다.")
        }
    }

    private var visible: [MenuBarEntry] { filtered(store.entries, query: query) }

    private var listScreen: some View {
        VStack(spacing: 0) {
            Group {
                if store.isScanning && store.entries.isEmpty {
                    placeholder(title: "조회 중…", progress: true)
                } else if store.hasScanned && store.entries.isEmpty {
                    placeholder(symbol: "menubar.rectangle", title: "접근 가능한 메뉴 막대 항목을 찾지 못했습니다",
                                detail: "macOS가 접근성으로 알려 주지 않은 항목은 표시할 수 없습니다", retry: true)
                } else if visible.isEmpty && !store.entries.isEmpty {
                    placeholder(symbol: "magnifyingglass", title: "검색 결과가 없습니다", detail: "검색어를 바꾸거나 지워 보세요")
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .searchable(text: $query, prompt: "앱 또는 항목 이름")
        .toolbar {
            ToolbarItem {
                Button { store.refresh() } label: { Label("새로고침", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
                    .disabled(store.isScanning || store.requestInFlight)
                    .help("목록 새로고침 (⌘R)")
            }
        }
    }

    private var list: some View {
        List(visible, selection: $selection) { entry in
            EntryRow(store: store, entry: entry, isSelected: selection == entry.id, isHovered: hovered == entry.id) { quitTarget = entry }
                .frame(maxWidth: contentWidth)
                .frame(maxWidth: .infinity)
                .onHover { inside in
                    if inside { hovered = entry.id } else if hovered == entry.id { hovered = nil }
                }
                .listRowBackground(rowBackground(entry.id))
                .listRowSeparator(.hidden)
        }
        .scrollContentBackground(.hidden)
        .onKeyPress(.return) {
            guard let entry = visible.first(where: { $0.id == selection }) else { return .ignored }
            store.openMenu(entry)
            return .handled
        }
    }

    /// 기본 행은 배경 없이 두고, 마우스 오버는 한 단계 올린 표면, 선택은 강조색 얇은 선으로 구분한다.
    private func rowBackground(_ id: String) -> some View {
        let selected = selection == id
        return ZStack {
            // 시스템 기본 선택 띠가 둥근 선택 표시와 겹쳐 그려지지 않도록 선택 행은 행 전체를 배경색으로 덮는다.
            if selected { Theme.background }
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Theme.selection : hovered == id ? Theme.raised : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.accent.opacity(0.55) : Color.clear))
                .frame(maxWidth: contentWidth + 24)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
        }
    }

    private func placeholder(symbol: String? = nil, title: String, detail: String? = nil,
                             progress: Bool = false, retry: Bool = false) -> some View {
        VStack(spacing: 8) {
            if progress { ProgressView().controlSize(.small).padding(.bottom, 4) }
            if let symbol {
                Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Theme.muted)
                    .padding(.bottom, 4).accessibilityHidden(true)
            }
            Text(title).font(.system(size: 13, weight: .medium))
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            if retry {
                Button("새로고침") { store.refresh() }.buttonStyle(ThemedButtonStyle(prominent: true)).padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
        .padding(32)
    }

    private var footer: some View {
        let groups = groupFailures(store.failures)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(store.isScanning ? "조회 중…" : "발견한 항목 \(store.entries.count)개 · 조회한 앱 \(store.scannedApps)개")
                    .foregroundStyle(Theme.secondary)
                if let first = groups.first {
                    Label("일부 앱 조회 실패 \(store.failures.count)건 — \(first.appName)(\(first.reason))"
                          + (first.count > 1 ? " \(first.count)건" : "") + (groups.count > 1 ? " 외 \(groups.count - 1)곳" : ""),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warning)
                        .lineLimit(1).truncationMode(.tail)
                    Button("자세히") { showFailures = true }
                        .buttonStyle(.link)
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("조회 실패 자세히 보기")
                        .popover(isPresented: $showFailures, arrowEdge: .top) { FailureList(groups: groups) }
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            Text("메뉴는 원래 메뉴 막대 위치에서 열립니다. 노치 영역과 겹치는 항목은 메뉴가 열려도 보이지 않을 수 있습니다.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .monospacedDigit()
        .frame(maxWidth: contentWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

private struct FailureList: View {
    let groups: [FailureGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("조회하지 못한 앱").font(.system(size: 13, weight: .semibold))
            // 실패한 앱이 많아도 잘리지 않게, 행 높이를 고정하고 일정 높이를 넘으면 스크롤한다.
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(groups, id: \.self) { group in
                        HStack(spacing: 12) {
                            Text(group.appName).lineLimit(1)
                            Spacer(minLength: 12)
                            Text(group.reason).foregroundStyle(Theme.secondary)
                            Text("\(group.count)건").foregroundStyle(Theme.secondary).frame(minWidth: 28, alignment: .trailing)
                        }
                        .font(.system(size: 12)).monospacedDigit()
                        .frame(height: 20)
                    }
                }
            }
            .frame(height: min(CGFloat(groups.count) * 24, 240))
            Text("다음 새로고침 때 다시 조회합니다").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(minWidth: 300, alignment: .leading)
    }
}

private struct EntryRow: View {
    @ObservedObject var store: Store
    let entry: MenuBarEntry
    let isSelected: Bool
    let isHovered: Bool
    let onQuit: () -> Void

    var body: some View {
        let status = store.rowStatus[entry.id]
        let quit = store.quitStates[entry.pid]
        HStack(spacing: 12) {
            Image(nsImage: NSRunningApplication(processIdentifier: entry.pid)?.icon ?? NSImage(named: NSImage.applicationIconName)!)
                .resizable().frame(width: 28, height: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1).help(entry.displayName)
                HStack(spacing: 4) {
                    Text(entry.appName).lineLimit(1)
                    if entry.overlapsNotch {
                        Text("·")
                        Image(systemName: "rectangle.topthird.inset.filled").accessibilityHidden(true)
                        Text("노치 영역과 겹침").lineLimit(1)
                    }
                }
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                if let text = statusText(status) { line(text) }
                if let text = quitText(quit) { line(text) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                if entry.menuAction != nil {
                    Button("메뉴 열기") { store.openMenu(entry) }
                        .buttonStyle(ThemedButtonStyle(prominent: isSelected, quiet: !isSelected && !isHovered))
                        .disabled(!canOpenMenu(status))
                        .accessibilityLabel("\(entry.appName) \(entry.displayName) 메뉴 열기")
                } else {
                    Text("메뉴 열기 미지원").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                appMenu(quit)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu {
            if entry.menuAction != nil {
                Button("메뉴 열기") { store.openMenu(entry) }.disabled(!canOpenMenu(status))
            }
            if entry.ownerAppURL != nil {
                Divider()
                Button("앱 열기") { store.openApp(entry) }
                Button("앱 종료…", action: onQuit).disabled(!canQuit(quit))
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// 앱 단위 동작(앱 열기·앱 종료)은 소유 앱이 확인된 행에만 보조 메뉴로 둔다. 없는 행도 같은 폭을 비워 버튼 열을 맞춘다.
    @ViewBuilder private func appMenu(_ quit: QuitState?) -> some View {
        if entry.ownerAppURL != nil {
            Menu {
                Button("앱 열기") { store.openApp(entry) }
                Button("앱 종료…", action: onQuit).disabled(!canQuit(quit))
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(Theme.secondary)
            .fixedSize()
            .frame(width: 28)
            .help("앱 열기 또는 앱 종료")
            .accessibilityLabel("\(entry.appName) 앱 작업")
        } else {
            Color.clear.frame(width: 28, height: 1).accessibilityHidden(true)
        }
    }

    private func canOpenMenu(_ status: RowStatus?) -> Bool {
        !store.requestInFlight && !store.isScanning && status?.isUncertain != true
    }

    private func canQuit(_ quit: QuitState?) -> Bool { quit != .requested && !store.isScanning }

    private func line(_ text: (String, Color)) -> some View {
        Text(text.0).font(.system(size: 11)).foregroundStyle(text.1).fixedSize(horizontal: false, vertical: true)
    }

    private func quitText(_ state: QuitState?) -> (String, Color)? {
        switch state {
        case nil, .terminated: return nil
        case .requested: return ("종료 요청을 보냈습니다 · 앱이 종료되는지 확인하는 중", Theme.secondary)
        case .stillRunning: return ("종료 요청됨 · 앱이 아직 실행 중입니다(저장 확인 대기 등). 다시 요청하지 않았습니다", Theme.warning)
        case .notAccepted: return ("앱이 종료 요청을 받아들이지 않았습니다", Theme.danger)
        }
    }

    private func statusText(_ status: RowStatus?) -> (String, Color)? {
        switch status {
        case nil: return nil
        case .requesting: return ("요청 중…", Theme.secondary)
        case .sent: return ("메뉴 열기 요청을 보냈습니다", Theme.secondary)
        case .noResponse: return ("응답 없음 · 이미 실행됐을 수 있어 다시 보내지 않았습니다. 새로고침하면 다시 시도할 수 있습니다", Theme.warning)
        case .unconfirmed(let code): return ("결과 미확인(오류 \(code)) · 메뉴가 열렸을 수 있어 다시 보내지 않았습니다. 새로고침하면 다시 시도할 수 있습니다", Theme.warning)
        case .failed(let message): return (message, Theme.danger)
        }
    }
}

private struct PermissionView: View {
    @ObservedObject var store: Store

    var body: some View {
        let revoked = store.permission == .revoked
        let denied = store.lastCheck?.trusted == false
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(revoked ? "손쉬운 사용 권한이 해제되었습니다" : "손쉬운 사용 권한이 필요합니다")
                        .font(.system(size: 20, weight: .semibold))
                    Text(revoked
                         ? "실행 중에 권한이 해제되어 조회와 메뉴 열기를 멈췄습니다. 다시 허용하면 이어서 쓸 수 있습니다."
                         : "다른 앱의 메뉴 막대 항목을 읽고 메뉴를 열려면 이 앱에 손쉬운 사용 권한이 필요합니다. 화면 녹화 권한은 쓰지 않으며, 모든 처리는 이 Mac 안에서만 이루어집니다.")
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 20) {
                    Step(number: 1, title: "시스템 설정에서 이 앱을 켭니다",
                         detail: "개인정보 보호 및 보안 > 손쉬운 사용에서 켭니다. ‘권한 요청’을 누르면 macOS가 확인 창을 띄워 설정으로 안내합니다.") {
                        HStack(spacing: 8) {
                            Button("권한 요청") { store.requestPermission() }.buttonStyle(ThemedButtonStyle(prominent: true))
                            Button("시스템 설정 열기") { store.openSettings() }.buttonStyle(ThemedButtonStyle())
                        }
                    }
                    Step(number: 2, title: "돌아와서 권한을 확인합니다", detail: nil) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("권한 다시 확인") { store.refresh() }.buttonStyle(ThemedButtonStyle())
                            Label(permissionCheckMessage(trusted: store.lastCheck?.trusted,
                                                         time: store.lastCheck?.date.formatted(date: .omitted, time: .standard) ?? ""),
                                  systemImage: denied ? "exclamationmark.circle" : "clock")
                                .font(.system(size: 12))
                                .foregroundStyle(denied ? Theme.warning : Theme.secondary)
                        }
                    }
                }
                recovery
            }
            .padding(32)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("설정에서 켜져 있는데도 허용되지 않을 때").font(.system(size: 13, weight: .semibold))
                Text("앱을 다시 빌드하거나 교체하면 시스템에 남은 이전 허용 기록과 현재 앱이 맞지 않을 수 있습니다. 이때는 토글을 껐다 켜거나 앱을 다시 실행하는 것만으로 해결되지 않습니다.")
                    .foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                numbered(1, "손쉬운 사용 목록에서 이 앱 항목을 선택하고 − 버튼으로 제거합니다.")
                numbered(2, "‘이 앱 위치 열기’로 Finder에서 현재 앱을 선택한 뒤, 목록의 + 버튼으로 다시 추가하고 켭니다.")
                numbered(3, "‘권한 다시 확인’을 누릅니다. 반영되지 않으면 앱을 다시 실행하세요.")
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("현재 실행 중인 앱").font(.system(size: 11)).foregroundStyle(Theme.muted)
                HStack(alignment: .center, spacing: 12) {
                    Text(Bundle.main.bundleURL.path)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("이 앱 위치 열기") { store.revealBundle() }.buttonStyle(ThemedButtonStyle())
                }
            }
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline))
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).").monospacedDigit().foregroundStyle(Theme.secondary).frame(width: 16, alignment: .trailing)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Step<Content: View>: View {
    let number: Int
    let title: String
    let detail: String?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .frame(width: 22, height: 22)
                .background(Theme.raised, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline))
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let detail {
                        Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
        }
    }
}
