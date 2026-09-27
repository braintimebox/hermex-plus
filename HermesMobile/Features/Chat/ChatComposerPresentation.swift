import SwiftUI

/// Shared geometry for Sessions and the text-only Bot composer.
enum ChatComposerMetrics {
    static let cardCornerRadius: CGFloat = 26
    static let actionSize: CGFloat = 44
    /// HERMEX-FORK: размер элементов строки в развёрнутом состоянии. Четыре круга по
    /// 44pt съедали поле ввода: телеметрия 3.9.14 показала `field w=194` против 338
    /// в свёрнутом виде, и строка выглядела перегруженной. Свёрнутый вид остаётся
    /// эталонным — 44pt там не меняются.
    static let compactActionSize: CGFloat = 34
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
            .adaptiveGlass(.regular, isInteractive: true, fallbackMaterial: .ultraThinMaterial, in: shape)
            .clipShape(shape)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 14, y: 6)
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
