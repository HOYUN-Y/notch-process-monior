import AppKit
import MenuBarKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: Store
    @State private var query = ""
    @State private var selection: String?
    @State private var quitTarget: MenuBarEntry?

    var body: some View {
        Group {
            if store.permission == .granted { listScreen } else { PermissionView(store: store) }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
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
                    message("조회 중…", progress: true)
                } else if store.hasScanned && store.entries.isEmpty {
                    message("접근 가능한 메뉴 막대 항목을 찾지 못했습니다. macOS가 접근성으로 알려 주지 않은 항목은 표시할 수 없습니다.", retry: true)
                } else if visible.isEmpty && !store.entries.isEmpty {
                    message("검색 결과가 없습니다. 검색어를 바꾸거나 지워 보세요.")
                } else {
                    List(visible, selection: $selection) { entry in
                        EntryRow(store: store, entry: entry) { quitTarget = entry }
                            .listRowBackground(Theme.background)
                            .listRowSeparatorTint(Theme.border)
                    }
                    .scrollContentBackground(.hidden)
                    .onKeyPress(.return) {
                        guard let entry = visible.first(where: { $0.id == selection }) else { return .ignored }
                        store.openMenu(entry)
                        return .handled
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .searchable(text: $query, prompt: "앱 이름 또는 항목 이름")
        .toolbar {
            ToolbarItem {
                Button { store.refresh() } label: { Label("새로고침", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
                    .disabled(store.isScanning || store.requestInFlight)
                    .help("목록 새로고침 (⌘R)")
            }
        }
    }

    private func message(_ text: String, progress: Bool = false, retry: Bool = false) -> some View {
        VStack(spacing: 12) {
            if progress { ProgressView().controlSize(.small) }
            Text(text).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            if retry { Button("새로고침") { store.refresh() }.buttonStyle(ThemedButtonStyle(prominent: true)) }
        }
        .padding(32)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.isScanning ? "조회 중…" : "발견한 항목 \(store.entries.count)개 · 조회한 앱 \(store.scannedApps)개")
            if !store.failures.isEmpty {
                Text("일부 앱 조회 실패 \(store.failures.count)건: " + store.failures.map { "\($0.appName)(\($0.reason))" }.joined(separator: ", "))
                    .foregroundStyle(Theme.warning).lineLimit(2)
            }
            Text("메뉴는 원래 메뉴 막대 위치에서 열립니다. 노치 영역과 겹치는 항목은 메뉴가 열려도 보이지 않을 수 있습니다.")
        }
        .font(.caption).foregroundStyle(Theme.secondary)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

private struct EntryRow: View {
    @ObservedObject var store: Store
    let entry: MenuBarEntry
    let onQuit: () -> Void

    var body: some View {
        let status = store.rowStatus[entry.id]
        let quit = store.quitStates[entry.pid]
        HStack(spacing: 12) {
            Image(nsImage: NSRunningApplication(processIdentifier: entry.pid)?.icon ?? NSImage(named: NSImage.applicationIconName)!)
                .resizable().frame(width: 32, height: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(.body.weight(.medium)).lineLimit(1)
                Text(entry.appName + (entry.overlapsNotch ? " · 노치 영역과 겹침" : ""))
                    .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                if let text = statusText(status) {
                    Text(text.0).font(.caption).foregroundStyle(text.1)
                }
                if let text = quitText(quit) {
                    Text(text.0).font(.caption).foregroundStyle(text.1)
                }
            }
            Spacer(minLength: 8)
            if entry.ownerAppURL != nil {
                Button("앱 열기") { store.openApp(entry) }
                    .buttonStyle(ThemedButtonStyle())
                    .accessibilityLabel("\(entry.appName) 앱 열기")
                Button("앱 종료", action: onQuit)
                    .buttonStyle(ThemedButtonStyle())
                    .disabled(quit == .requested || store.isScanning)
                    .accessibilityLabel("\(entry.appName) 앱 종료 요청")
            }
            if entry.menuAction != nil {
                Button("메뉴 열기") { store.openMenu(entry) }
                    .buttonStyle(ThemedButtonStyle(prominent: true))
                    .disabled(store.requestInFlight || store.isScanning || status?.isUncertain == true)
                    .accessibilityLabel("\(entry.appName) \(entry.displayName) 메뉴 열기")
            } else {
                Text("메뉴 열기 미지원").font(.caption).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func quitText(_ state: QuitState?) -> (String, Color)? {
        switch state {
        case nil, .terminated: return nil
        case .requested: return ("종료 요청됨. 앱이 종료되는지 확인하는 중입니다.", Theme.secondary)
        case .stillRunning: return ("종료 요청됨. 앱이 아직 실행 중입니다(저장 확인 대기 등). 다시 요청하지 않았습니다.", Theme.warning)
        case .notAccepted: return ("앱이 종료 요청을 받아들이지 않았습니다.", Theme.danger)
        }
    }

    private func statusText(_ status: RowStatus?) -> (String, Color)? {
        switch status {
        case nil: return nil
        case .requesting: return ("요청 중…", Theme.secondary)
        case .sent: return ("메뉴 열기 요청을 보냈습니다.", Theme.secondary)
        case .noResponse: return ("응답이 없습니다. 요청은 이미 실행됐을 수 있어 다시 보내지 않았습니다. 새로고침 후 확인하세요.", Theme.warning)
        case .unconfirmed(let code): return ("macOS가 결과를 확인해 주지 않았습니다(오류 \(code)). 메뉴가 열렸을 수 있으니 메뉴 막대를 확인하세요. 요청을 다시 보내지 않았습니다. 새로고침하면 다시 시도할 수 있습니다.", Theme.warning)
        case .failed(let message): return (message, Theme.danger)
        }
    }
}

private struct PermissionView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.permission == .revoked ? "손쉬운 사용 권한이 해제되었습니다" : "손쉬운 사용 권한이 필요합니다")
                .font(.title2.weight(.semibold))
            Text(store.permission == .revoked
                 ? "실행 중에 권한이 해제되어 조회와 메뉴 열기를 중단했습니다. 시스템 설정에서 다시 허용한 뒤 ‘권한 다시 확인’을 누르세요. 반영되지 않으면 앱을 다시 실행하세요."
                 : "다른 앱의 메뉴 막대 항목을 조회하고 메뉴 열기를 요청하려면 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 이 앱을 허용해야 합니다. 화면 녹화 권한은 쓰지 않으며, 모든 처리는 이 Mac 안에서만 이루어집니다.")
                .foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("권한 요청") { store.requestPermission() }.buttonStyle(ThemedButtonStyle(prominent: true))
                Button("시스템 설정 열기") { store.openSettings() }.buttonStyle(ThemedButtonStyle())
                Button("권한 다시 확인") { store.refresh() }.buttonStyle(ThemedButtonStyle())
            }
        }
        .padding(32).frame(maxWidth: 520, maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity)
    }
}
