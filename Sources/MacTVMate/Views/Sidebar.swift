import SwiftUI

/// TiViMate's left menu: Search, TV, Movies, Shows, Recordings, My list … Settings.
/// A compact rail with a small label under each icon (no hover expansion, so it never covers content).
struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    static var collapsedWidth: CGFloat { Theme.s(76) }

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let screen: Screen?
    }

    private let items: [Item] = [
        Item(id: "TV", icon: "tv", screen: .guide),
        Item(id: "Movies", icon: "film", screen: .movies),
        Item(id: "Shows", icon: "play.rectangle.on.rectangle", screen: .shows),
        Item(id: "Recordings", icon: "record.circle", screen: .recordings),
        Item(id: "My list", icon: "bookmark", screen: .myList),
    ]

    var body: some View {
        VStack(spacing: Theme.s(4)) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: Theme.uiScale * 24))
                .foregroundStyle(Theme.accent)
                .padding(.top, Theme.s(34)).padding(.bottom, Theme.s(20))

            row(icon: "magnifyingglass", title: "Search", selected: model.showSearch) { model.openSearch() }
            ForEach(items) { item in
                row(icon: item.icon, title: item.id, selected: model.screen == item.screen && !model.showSearch && !model.showSettings) {
                    if let s = item.screen { model.showSettings = false; model.screen = s }
                }
            }
            Spacer()
            row(icon: "gearshape", title: "Settings", selected: model.showSettings) { model.showSettings.toggle() }
                .padding(.bottom, Theme.s(16))
        }
        .padding(.horizontal, Theme.s(6))
        .frame(width: Self.collapsedWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
    }

    private func row(icon: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.s(4)) {
                Image(systemName: icon).font(.system(size: Theme.uiScale * 18, weight: selected ? .semibold : .regular))
                Text(title).font(.system(size: Theme.uiScale * 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.s(8))
            .background(selected ? Theme.focus : .clear, in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(selected ? Theme.focusText : Theme.text.opacity(0.8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
