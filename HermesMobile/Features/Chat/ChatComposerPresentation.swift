import SwiftUI

/// Shared geometry for Sessions and the text-only Bot composer.
enum ChatComposerMetrics {
    static let cardCornerRadius: CGFloat = 26
    static let actionSize: CGFloat = 44
    static let pillInset: CGFloat = 5
}

struct ChatComposerSurfaceStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let isExpanded: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: isExpanded ? ChatComposerMetrics.cardCornerRadius
                : (ChatComposerMetrics.actionSize + ChatComposerMetrics.pillInset * 2) / 2,
            style: .continuous
        )
    }

    func body(content: Content) -> some View {
        content
            .background(
                shape.fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
            )
            .overlay(
                shape.stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
            .clipShape(shape)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, y: 3)
    }
}

struct ChatComposerActionAppearance {
    let isStop: Bool
    let isDisabled: Bool
    let colorScheme: ColorScheme
    let tintsPrimaryActions: Bool
    let themeHex: String

    private var usesTheme: Bool {
        PrimaryActionTintSettings.usesThemeColor(
            isEnabled: tintsPrimaryActions, controlIsEnabled: !isDisabled
        )
    }

    var background: Color {
        if isStop { return Color.red.opacity(colorScheme == .dark ? 0.22 : 0.14) }
        if usesTheme { return HeaderLogoColor.color(for: themeHex) }
        if isDisabled { return colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12) }
        return colorScheme == .dark ? .white : .black
    }

    var foreground: Color {
        if isStop { return .red }
        if usesTheme { return HeaderLogoColor.prefersDarkForeground(for: themeHex) ? .black : .white }
        if isDisabled { return Color(.secondaryLabel) }
        return colorScheme == .dark ? .black : .white
    }
}
