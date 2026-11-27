import SwiftUI

/// The five sections the app is organised into.
///
/// The order is the dock's order, and it is data rather than layout: the dock renders
/// `allCases` and hides what is switched off, so a section that disappears never leaves a
/// hole behind it.
enum AppTab: String, CaseIterable, Identifiable {
    case groups
    case bots
    case chats
    case kanban
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groups: String(localized: "Groups")
        case .bots: String(localized: "Bots")
        case .chats: String(localized: "Chats")
        case .kanban: String(localized: "Kanban")
        case .settings: String(localized: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .groups: "person.3"
        case .bots: "cpu"
        case .chats: "bubble.left.and.bubble.right"
        case .kanban: "rectangle.split.3x1"
        case .settings: "gearshape"
        }
    }
}

/// The dock, drawn by the app.
///
/// Not `TabView`: on iPad iOS 18 puts tabs on top or in a `.sidebarAdaptable` sidebar, and
/// the sidebar takes away the master-detail column pair the tablet has today. A row we lay
/// out keeps the same five sections at the bottom on both devices.
///
/// It is attached as a bottom safe-area inset rather than drawn over the content, which is
/// what keeps the composer — itself a bottom inset — above the dock instead of underneath
/// it.
/// Reports the dock's own height so a floating control can sit above it instead of
/// guessing a constant that goes stale when Dynamic Type or the safe area changes.
struct DockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AppDock: View {
    @Binding var selection: AppTab
    /// Sections that exist right now, in the order the owner put them in.
    let available: [AppTab]
    @AppStorage(NavigationPreferences.titlesKey) private var titlesRaw = ""

    private func title(for tab: AppTab) -> String {
        NavigationPreferences.titles(from: titlesRaw)["dock.\(tab.rawValue)"] ?? tab.title
    }

    var body: some View {
        HStack(spacing: 0) {
            // `available` carries the owner's order. The old shape — `allCases.filter(
            // available.contains)` — iterated the enum and only checked membership, so a
            // reorder was stored and never drawn.
            ForEach(available) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: selection == tab ? .semibold : .regular))
                            .frame(height: 24)
                        Text(title(for: tab))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(title(for: tab)))
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 4)
        .background(.bar)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: DockHeightKey.self, value: proxy.size.height)
            }
        }
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
