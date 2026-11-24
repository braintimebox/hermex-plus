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
struct AppDock: View {
    @Binding var selection: AppTab
    /// Sections that exist right now: Bots behind its gate, Kanban behind its flag.
    let available: [AppTab]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases.filter(available.contains)) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: selection == tab ? .semibold : .regular))
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 4)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
