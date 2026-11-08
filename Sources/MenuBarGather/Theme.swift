import AppKit
import SwiftUI

/// navy & slate. 어두운 모드는 navy 배경, 밝은 모드는 slate 계열 밝은 배경.
enum Theme {
    static let background = dynamic(dark: 0x0F172A, light: 0xF1F5F9)
    static let panel = dynamic(dark: 0x1E293B, light: 0xFFFFFF)
    static let border = dynamic(dark: 0x334155, light: 0xCBD5E1)
    static let text = dynamic(dark: 0xF1F5F9, light: 0x0F172A)
    static let secondary = dynamic(dark: 0x94A3B8, light: 0x475569)
    static let accent = dynamic(dark: 0x60A5FA, light: 0x1D4ED8)
    static let onAccent = dynamic(dark: 0x0F172A, light: 0xFFFFFF)
    static let warning = dynamic(dark: 0xFCD34D, light: 0x92400E)
    static let danger = dynamic(dark: 0xFCA5A5, light: 0xB91C1C)

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

struct ThemedButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(prominent ? Theme.onAccent : Theme.text)
            .background(prominent ? Theme.accent : Theme.panel, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(prominent ? Color.clear : Theme.border))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
