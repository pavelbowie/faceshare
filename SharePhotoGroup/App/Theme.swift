//
//  Theme.swift
//  SharePhotoGroup
//
//  Created by Pavel Mac on 19/04/25
//

import SwiftUI

// MARK: - Color Theme

struct AppColors {
    // MARK: Backgrounds
    static var baseBackground: Color {
        Color(light: "#F9F9FB", dark: "#111113") // Cloud White / Soft Graphite
    }
    static var cardSurface: Color {
        Color(light: "#FFFFFF", dark: "#1A1A1D")
    }
    static var sectionBackground: Color {
        Color(light: "#EFEFF2", dark: "#1C1C1F")
    }
    static var divider: Color {
        Color(light: "#E0E0E5", dark: "#2A2A2E")
    }
    
    // MARK: Primary & Secondary
    static var primary: Color { Color(hex: "7B61FF") } // Memento Violet
    static var emotion: Color { Color(hex: "FFD6C2") } // Peach Blush
    static var accent: Color { Color(hex: "7B61FF") } // Memento Violet (strong accent)
    static var success: Color { Color(hex: "B8E986") } // Pale Green
    static var coolGray: Color { Color(light: "#9EA4B0", dark: "#A2A2AA") } // Secondary text, placeholders
    static var graphiteBlack: Color { Color(hex: "111113") } // Core text on light
    static var cloudWhite: Color { Color(hex: "F9F9FB") } // Core text on dark
    
    // MARK: Semantic Roles
    static var background: Color { baseBackground }
    static var cardBackground: Color { cardSurface }
    static var section: Color { sectionBackground }
    static var border: Color { divider }
    static var textPrimary: Color {
        Color(light: "#111113", dark: "#F9F9FB")
    }
    static var textSecondary: Color { coolGray }
    static var error: Color { Color(hex: "FF3B30") }
    
    // MARK: Special Chips & UI
    static var faceTag: Color { accent } // Face tags, names
    static var liveChip: Color { success } // "Live" badge
    static var commentBubble: Color { emotion } // Comment bubble fill
}

// MARK: - Typography
struct AppTypography {
    // Font weights
    static let display = Font.system(size: 28, weight: .bold)
    static let sectionTitle = Font.system(size: 20, weight: .semibold)
    static let bodyText = Font.system(size: 16, weight: .regular)
    static let subtext = Font.system(size: 14, weight: .light)
    static let button = Font.system(size: 16, weight: .medium)
    
    // Dynamic type support
    static func display(for textStyle: Font.TextStyle) -> Font {
        return .system(textStyle, design: .rounded).weight(.bold)
    }
    
    static func sectionTitle(for textStyle: Font.TextStyle) -> Font {
        return .system(textStyle, design: .rounded).weight(.semibold)
    }
    
    static func bodyText(for textStyle: Font.TextStyle) -> Font {
        return .system(textStyle, design: .rounded).weight(.regular)
    }
    
    static func subtext(for textStyle: Font.TextStyle) -> Font {
        return .system(textStyle, design: .rounded).weight(.light)
    }
    
    static func button(for textStyle: Font.TextStyle) -> Font {
        return .system(textStyle, design: .rounded).weight(.medium)
    }
}

// MARK: - Spacing & Layout
struct AppSpacing {
    static let horizontalPadding: CGFloat = 16
    static let sectionGap: CGFloat = 20
    static let cardCornerRadius: CGFloat = 12
    static let buttonCornerRadius: CGFloat = 10
    static let avatarSize: CGFloat = 36
    static let avatarSizeLarge: CGFloat = 44
    static let iconSize: CGFloat = 24
    static let imageSpacing: CGFloat = 8
    
    // Grid system
    static let gridUnit: CGFloat = 8
    static let grid2x: CGFloat = gridUnit * 2
    static let grid3x: CGFloat = gridUnit * 3
    static let grid4x: CGFloat = gridUnit * 4
    static let grid5x: CGFloat = gridUnit * 5
}

// MARK: - Shadows
struct AppShadows {
    static let small = Shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    static let medium = Shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    static let large = Shadow(color: Color.black.opacity(0.2), radius: 16, x: 0, y: 8)
}

// MARK: - Animation
struct AppAnimation {
    static let standard = Animation.easeInOut(duration: 0.3)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let quick = Animation.easeInOut(duration: 0.15)
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundColor(AppColors.cardBackground)
            .padding(.horizontal, AppSpacing.grid3x)
            .padding(.vertical, AppSpacing.grid2x)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.buttonCornerRadius)
                    .fill(configuration.isPressed ? AppColors.primary.opacity(0.8) : AppColors.primary)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(AppAnimation.quick, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundColor(AppColors.primary)
            .padding(.horizontal, AppSpacing.grid3x)
            .padding(.vertical, AppSpacing.grid2x)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.buttonCornerRadius)
                    .stroke(AppColors.primary, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: AppSpacing.buttonCornerRadius)
                            .fill(AppColors.cardBackground)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(AppAnimation.quick, value: configuration.isPressed)
    }
}

// MARK: - Card Style
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.horizontalPadding)
            .background(AppColors.cardBackground)
            .cornerRadius(AppSpacing.cardCornerRadius)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Face Tag Style
struct FaceTagStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppTypography.subtext)
            .foregroundColor(AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.grid2x)
            .padding(.vertical, AppSpacing.gridUnit)
            .background(AppColors.faceTag)
            .cornerRadius(AppSpacing.buttonCornerRadius)
    }
}

// MARK: - View Extensions
extension View {
    func cardStyle() -> some View {
        self.modifier(CardStyle())
    }
    
    func faceTagStyle() -> some View {
        self.modifier(FaceTagStyle())
    }
}

// MARK: - Dynamic Color Extension
extension Color {
    init(light: String, dark: String) {
        self.init(UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(Color(hex: dark))
            } else {
                return UIColor(Color(hex: light))
            }
        })
    }
    
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
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Shadow Struct
struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func shadow(_ shadow: Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
} 
