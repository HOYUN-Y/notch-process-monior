import AppKit
import SwiftUI

/// navy & slate. 어두운 모드는 navy 배경, 밝은 모드는 slate 계열 밝은 배경.
/// 표면은 배경 → 패널 → 선택/입력 세 단계, 강조색은 선택 행과 화면당 주 동작에만 쓴다.
enum Theme {
    static let background = dynamic(dark: 0x0F172A, light: 0xF8FAFC)
    static let panel = dynamic(dark: 0x131C31, light: 0xFFFFFF)
    static let raised = dynamic(dark: 0x1E293B, light: 0xEEF2F7)
    static let hairline = dynamic(dark: 0xF1F5F9, light: 0x0F172A, alpha: 0.1)
    static let text = dynamic(dark: 0xF1F5F9, light: 0x0F172A)
    static let secondary = dynamic(dark: 0x94A3B8, light: 0x475569)
    /// 보조 안내와 메타 정보용. 배경·패널 위에서만 쓴다(대비 5:1 이상).
    static let muted = dynamic(dark: 0x8391A7, light: 0x5B6B80)
    static let accent = dynamic(dark: 0x60A5FA, light: 0x1D4ED8)
    static let onAccent = dynamic(dark: 0x0F172A, light: 0xFFFFFF)
    static let selection = dynamic(dark: 0x1C2E4B, light: 0xE2E9F8)
    static let warning = dynamic(dark: 0xFCD34D, light: 0x92400E)
    static let danger = dynamic(dark: 0xFCA5A5, light: 0xB91C1C)

    private static func dynamic(dark: UInt32, light: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light, alpha: alpha)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// prominent: 강조색 채움(화면당 주 동작). quiet: 배경 없는 보조색 글자(반복되는 행 동작의 기본 상태).
/// 기본: 한 단계 올라온 표면과 얇은 경계선. 세 상태의 크기는 같아서 전환해도 배치가 흔들리지 않는다.
struct ThemedButtonStyle: ButtonStyle {
    var prominent = false
    var quiet = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(prominent ? Theme.onAccent : quiet ? Theme.secondary : Theme.text)
            .background(prominent ? Theme.accent : quiet ? Color.clear : Theme.raised, in: shape)
            .overlay(shape.strokeBorder(prominent || quiet ? Color.clear : Theme.hairline))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(shape)
    }
}
