import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let rail: CGFloat = model.screen == .player ? 0 : Sidebar.collapsedWidth
            let groupCol: CGFloat = model.screen == .guide && model.library.settings.showGroupColumn ? GroupColumn.width : 0
            let layout = GuideLayout(size: CGSize(width: geo.size.width - rail - groupCol, height: geo.size.height),
                                     sizeIndex: model.library.settings.guideSize)
            let videoRect: CGRect = {
                switch model.screen {
                case .guide: return layout.previewRect.offsetBy(dx: rail + groupCol, dy: 0)
                case .player: return CGRect(origin: .zero, size: geo.size)
                default: return CGRect(x: 0, y: 0, width: 1, height: 1)
                }
            }()

            ZStack(alignment: .topLeading) {
                Theme.bg.ignoresSafeArea()

                MPVVideoView(controller: model.player)
                    .frame(width: videoRect.width, height: videoRect.height)
                    .offset(x: videoRect.minX, y: videoRect.minY)
                    .opacity(model.screen.isBrowser ? 0 : 1)
                    .onTapGesture(count: 2) { model.toggleFullScreen() }

                HStack(spacing: 0) {
                    if model.screen != .player { Sidebar() }
                    switch model.screen {
                    case .guide:
                        if groupCol > 0 { GroupColumn() }
                        GuideScreen(layout: layout)
                    case .player:
                        PlayerOverlay(player: model.player)
                    case .movies:
                        VODBrowser(kind: .movies).id("movies")
                    case .shows:
                        VODBrowser(kind: .series).id("shows")
                    case .recordings:
                        RecordingsScreen()
                    case .myList:
                        MyListScreen()
                    }
                }

                if model.showSettings {
                    SettingsPanel()
                }

                if model.showSearch {
                    SearchOverlay()
                }

                if let r = model.recorder.dueReminder {
                    ReminderBanner(reminder: r)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !model.numberEntry.isEmpty {
                    Text(model.numberEntry)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(30)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.screen)
            .animation(.easeInOut(duration: 0.2), value: model.showSettings)
            .onAppear { model.guideVisibleSpan = layout.visibleSpan }
            .onChange(of: layout.visibleSpan) { _, v in model.guideVisibleSpan = v }
        }
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1000, minHeight: 620)
    }
}

/// TiViMate-style split: details + preview on top, grid below.
struct GuideLayout {
    let size: CGSize
    var sizeIndex = 1
    var topHeight: CGFloat { max(220, size.height * 0.38) }
    var previewRect: CGRect {
        let h = topHeight - 24
        let w = min(h * 16 / 9, size.width * 0.45)
        return CGRect(x: size.width - w - 16, y: 12, width: w, height: w * 9 / 16)
    }

    // TiViMate's guide geometry (dp on a 960-wide TV canvas): 190 channel column, 41 rows (medium font),
    // 160 per 30 minutes. Scaled to the window so proportions match; the visible time span follows the width.
    var scale: CGFloat { min(2, max(1, size.width / 960)) }
    var channelColumn: CGFloat { (190 * scale).rounded() }
    var rowHeight: CGFloat { (AppSettings.rowHeights[min(3, max(0, sizeIndex))] * scale).rounded() }
    var fontScale: CGFloat { [0.9, 1, 1.12, 1.3][min(3, max(0, sizeIndex))] }
    var slotWidth: CGFloat { 160 * scale }
    var pxPerSecond: CGFloat { slotWidth / 1800 }
    var visibleSpan: TimeInterval { TimeInterval((size.width - channelColumn) / pxPerSecond) }
}
