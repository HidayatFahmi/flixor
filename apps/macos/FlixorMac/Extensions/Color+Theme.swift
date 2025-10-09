//
//  Color+Theme.swift
//  FlixorMac
//
//  Theme colors matching the web app
//

import SwiftUI

extension Color {
    // MARK: - Brand Colors (Netflix Red)
    static let brand = Color(hex: "#e50914")
    static let brandHover = Color(hex: "#b20710")

    // MARK: - Background Colors
    static let backgroundPrimary = Color(hex: "#0a0a0a")
    static let backgroundSecondary = Color(hex: "#0f0f10")
    static let backgroundTertiary = Color(hex: "#141414")

    // MARK: - Neutral Grays
    static let neutral800 = Color(hex: "#262626")
    static let neutral900 = Color(hex: "#171717")

    // MARK: - Gradient Colors
    static let gradientRedStart = Color(red: 122/255, green: 22/255, blue: 18/255).opacity(0.44)
    static let gradientRedMid = Color(red: 122/255, green: 22/255, blue: 18/255).opacity(0.20)
    static let gradientTealStart = Color(red: 20/255, green: 76/255, blue: 84/255).opacity(0.42)
    static let gradientTealMid = Color(red: 20/255, green: 76/255, blue: 84/255).opacity(0.20)

    // MARK: - Helper
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
