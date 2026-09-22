import SwiftUI

// 与 Windows 版 ThemePalette.cs 配色一一对应
struct ThemePalette {
    let card: Color
    let stroke: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let accentText: Color
    let accentHover: Color
    let secondaryBtn: Color
    let success: Color
    let warn: Color
    let progressTrack: Color
    let isDark: Bool
    let cardTranslucent: Bool

    static func forTheme(_ theme: String) -> ThemePalette {
        switch theme {
        case "light":
            return ThemePalette(
                card: Color(hex: 0xF3F3F3), stroke: Color(hex: 0xE0E0E0),
                textPrimary: Color(hex: 0x1A1A1A), textSecondary: Color(hex: 0x5D5D5D), textTertiary: Color(hex: 0x8A8A8A),
                accent: Color(hex: 0x0067C0), accentText: .white, accentHover: Color(hex: 0x1A7AD1),
                secondaryBtn: .white, success: Color(hex: 0x0F7B0F), warn: Color(hex: 0x9D5D00),
                progressTrack: Color(hex: 0xE5E5E5), isDark: false, cardTranslucent: true)
        case "pure":
            return ThemePalette(
                card: .white, stroke: Color(hex: 0xE8E8E8),
                textPrimary: Color(hex: 0x111111), textSecondary: Color(hex: 0x606060), textTertiary: Color(hex: 0x909090),
                accent: Color(hex: 0x005FB8), accentText: .white, accentHover: Color(hex: 0x1A70C8),
                secondaryBtn: Color(hex: 0xF5F5F5), success: Color(hex: 0x0F7B0F), warn: Color(hex: 0x8A5A00),
                progressTrack: Color(hex: 0xEEEEEE), isDark: false, cardTranslucent: false)
        default: // dark
            return ThemePalette(
                card: Color(hex: 0x2A2A2A), stroke: Color(hex: 0x3A3A3A),
                textPrimary: .white, textSecondary: Color(hex: 0x9A9A9A), textTertiary: Color(hex: 0x6E6E6E),
                accent: Color(hex: 0x60CDFF), accentText: Color(hex: 0x00303F), accentHover: Color(hex: 0x7AD4FF),
                secondaryBtn: Color(hex: 0x2F2F2F), success: Color(hex: 0x6CCB7A), warn: Color(hex: 0xF5C542),
                progressTrack: Color(hex: 0x3A3A3A), isDark: true, cardTranslucent: false)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
