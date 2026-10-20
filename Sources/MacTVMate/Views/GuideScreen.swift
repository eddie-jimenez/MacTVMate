import SwiftUI

struct GuideScreen: View {
    @EnvironmentObject var model: AppModel
    let layout: GuideLayout

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ProgrammeDetails()
                    .padding(.leading, 24).padding(.top, 18).padding(.trailing, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Color.clear.frame(width: layout.previewRect.width + 32)
                    .overlay(alignment: .topLeading) {
                        PreviewControls(player: model.player)
                            .frame(width: layout.previewRect.width, height: layout.previewRect.height)
                            .offset(x: 16, y: 12)
                    }
            }
            .frame(height: layout.topHeight)
            .background(alignment: .leading) {
                // Opaque everywhere except the preview "window", with the programme's art as a soft backdrop.
                HStack(spacing: 0) {
                    ZStack {
                        Theme.bg
                        if let p = model.guideSelectedProgramme, let art = model.meta.art(for: p) {
                            AsyncImage(url: art) { ph in
                                if let i = ph.image { i.resizable().aspectRatio(contentMode: .fill) } else { Color.clear }
                            }
                            .blur(radius: 40).opacity(0.35)
                            .overlay(LinearGradient(colors: [.clear, Theme.bg], startPoint: .top, endPoint: .bottom))
                            .clipped()
                        }
                    }
                    Color.clear.frame(width: layout.previewRect.width + 16)
                    Theme.bg.frame(width: 16)
                }
            }

            GuideHeader(layout: layout)
            GuideGrid(layout: layout)
        }
    }
}

struct ProgrammeDetails: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let ch = model.guideSelectedChannel
        let p = model.guideSelectedProgramme
        VStack(alignment: .leading, spacing: 8) {
            if let ch {
                HStack(spacing: 10) {
                    ChannelLogo(url: ch.logo, size: 28)
                    Text(verbatim: "\(ch.number)  \(ch.name)").font(.headline).foregroundStyle(Theme.dim).lineLimit(1)
                    FavouriteButton(channel: ch)
                }
            }
            let game = p.flatMap { prog in ch.flatMap { model.game(for: prog, channel: $0) } }
            HStack(alignment: .top, spacing: 16) {
                if let p, let icon = model.meta.art(for: p), p.kind != .sports {
                    AsyncImage(url: icon) { ph in
                        if let i = ph.image { i.resizable().aspectRatio(contentMode: .fit) } else { Color.clear }
                    }
                    .frame(width: 92, height: 136).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(p?.displayTitle ?? (ch == nil ? "No channels" : "No programme information"))
                        .font(.system(size: 26, weight: .semibold))
                        .lineLimit(2)
                    if let game { GameHeader(game: game) }
                    else if let p, p.kind != .other || p.isNew {
                        ProgrammeMeta(p: p)
                        EnrichmentLine(p: p)
                    }
                    if let p, let sub = p.subtitle, !sub.isEmpty, game == nil {
                        Text(sub).font(.callout.italic()).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                }
            }
            if let p {
                HStack(spacing: 8) {
                    Text("\(Theme.dayLabel(p.start))  \(Theme.range(p))  ·  \(Int(p.duration / 60)) min")
                        .foregroundStyle(Theme.dim)
                    if p.isLive(at: model.now) { Badge(text: "LIVE", color: Theme.live) }
                    if p.isEvent { Badge(text: "EVENT", color: .purple) }
                    if p.stop < model.now, ch?.hasCatchup == true { Badge(text: "CATCH-UP") }
                    if let ch, model.recorder.isScheduled(ch, p) { Badge(text: "REC", color: Theme.live) }
                    if let cat = p.category { Text(cat).foregroundStyle(Theme.faint) }
                }
                .font(.callout)
                if p.isLive(at: model.now) {
                    HStack {
                        ProgressLine(value: p.progress(at: model.now)).frame(maxWidth: 360)
                        Text("\(Int(p.stop.timeIntervalSince(model.now) / 60)) min left").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                if let desc = p.desc {
                    Text(desc).font(.callout).foregroundStyle(Theme.dim).lineLimit(3)
                }
                if !p.actors.isEmpty || !p.directors.isEmpty {
                    Text(([p.directors.isEmpty ? nil : "Dir. " + p.directors.prefix(2).joined(separator: ", "),
                           p.actors.isEmpty ? nil : p.actors.prefix(5).joined(separator: ", ")].compactMap { $0 }).joined(separator: "  ·  "))
                        .font(.caption).foregroundStyle(Theme.faint).lineLimit(1)
                }
            }
            if let ch { actions(ch, p).padding(.top, 4) }
            Spacer(minLength: 0)
            if let status = model.library.status {
                HStack { ProgressView().controlSize(.small); Text(status).foregroundStyle(Theme.dim) }
            } else if let err = model.library.error {
                Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(2)
            } else if let warn = model.library.guideWarning {
                Label(warn, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(2)
            }
        }
    }

    /// Watch · Watch from start · Record · Remind (TiViMate's programme menu).
    @ViewBuilder private func actions(_ ch: Channel, _ p: Programme?) -> some View {
        let now = model.now
        HStack(spacing: 8) {
            if p == nil || p!.isLive(at: now) {
                Button { model.play(ch) } label: { Label("Watch", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            if let p, p.stop <= now || p.isLive(at: now), ch.hasCatchup {
                Button { model.playCatchup(ch, p) } label: {
                    Label(p.isLive(at: now) ? "Watch from start" : "Watch (catch-up)", systemImage: "gobackward")
                }
            }
            if let p, p.stop > now {
                if let rec = model.recorder.recording(for: ch, p), rec.status == .scheduled || rec.status == .recording {
                    Button { model.recorder.cancel(rec) } label: {
                        Label(rec.status == .recording ? "Stop recording" : "Cancel recording", systemImage: "stop.circle")
                    }
                } else {
                    Button { model.record(ch, p) } label: { Label("Record", systemImage: "record.circle") }
                }
            } else if p == nil {
                Button { model.record(ch, nil) } label: { Label("Record 1 h", systemImage: "record.circle") }
            }
            if let p, p.start > now {
                if model.recorder.hasReminder(ch, p) {
                    Button { model.recorder.removeReminder(ch, p) } label: { Label("Reminder set", systemImage: "bell.fill") }
                } else {
                    Button { model.recorder.remind(ch, p) } label: { Label("Remind me", systemImage: "bell") }
                }
            }
        }
        .controlSize(.regular)
    }
}

/// TiViMate's group list next to the guide (Favourites first, always).
struct GroupColumn: View {
    @EnvironmentObject var model: AppModel
    static let width: CGFloat = 220

    var body: some View {
        let groups = columnGroups
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(groups) { g in
                        let sel = g.name == model.selectedGroup
                        HStack(spacing: 8) {
                            if g.name == ChannelGroup.favourites { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                            Text(g.name).lineLimit(1)
                            Spacer()
                            Text("\(g.count)").font(.caption).foregroundStyle(sel ? Theme.focusText.opacity(0.6) : Theme.faint)
                        }
                        .font(.system(size: 14 * (model.library.settings.guideSize >= 2 ? 1.1 : 1), weight: sel ? .semibold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(sel ? Theme.focus : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(sel ? Theme.focusText : Theme.text.opacity(0.9))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selectedGroup = g.name
                            model.guideRow = 0
                        }
                        .id(g.name)
                    }
                }
                .padding(.horizontal, 10).padding(.top, 40)
            }
            .onAppear { proxy.scrollTo(model.selectedGroup, anchor: .center) }
        }
        .frame(width: Self.width)
        .background(Theme.bg)
    }

    private var columnGroups: [ChannelGroup] {
        var g = model.library.groups
        if !g.contains(where: { $0.name == ChannelGroup.favourites }) {
            g.insert(ChannelGroup(name: ChannelGroup.favourites, count: 0), at: 0)
        }
        return g
    }
}

struct GuideHeader: View {
    @EnvironmentObject var model: AppModel
    let layout: GuideLayout

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(model.library.groups) { g in
                    Button("\(g.name) (\(g.count))") {
                        model.selectedGroup = g.name
                        model.guideRow = 0
                    }
                }
            } label: {
                Text(Theme.dayLabel(model.guideStart, withTime: false)).font(.callout.weight(.semibold)).foregroundStyle(Theme.accent).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .help("Pick a group")
            .padding(.horizontal, 12)
            .frame(width: layout.channelColumn, alignment: .leading)

            // Same scale as the grid below, so ticks line up with programme edges.
            ZStack(alignment: .leading) {
                ForEach(0..<Int((layout.visibleSpan / AppModel.slot).rounded(.up)), id: \.self) { i in
                    let t = model.guideStart.addingTimeInterval(Double(i) * AppModel.slot)
                    Text(Theme.time.string(from: t))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Theme.dim)
                        .offset(x: CGFloat(i) * layout.slotWidth + 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .clipped()
            .overlay(alignment: .trailing) {
            HStack(spacing: 4) {
                Button { model.guideShift(slots: -48) } label: { Image(systemName: "chevron.left.2") }.help("Previous day")
                Button { model.guideShift(slots: -2) } label: { Image(systemName: "chevron.left") }.help("Back 1 hour")
                Button("Now") { model.resetGuideToNow() }
                Button { model.guideShift(slots: 2) } label: { Image(systemName: "chevron.right") }.help("Forward 1 hour")
                Button { model.guideShift(slots: 48) } label: { Image(systemName: "chevron.right.2") }.help("Next day")
                Button { model.openSearch() } label: { Image(systemName: "magnifyingglass") }.help("Search (⌘F or /)")
                Button { model.toggleFullScreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("Watch full screen (⌘↩)").disabled(model.playing == nil)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .background(Theme.panel)
            }
        }
        .frame(height: max(30, 29 * layout.scale))
        .background(Theme.panel)
    }
}

struct GuideGrid: View {
    @EnvironmentObject var model: AppModel
    let layout: GuideLayout

    var body: some View {
        let channels = model.groupChannels
        GeometryReader { g in
            let span = layout.visibleSpan
            let start = model.guideStart
            let end = start.addingTimeInterval(span)
            let pxPerSec = layout.pxPerSecond

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    // Rows are identified by channel (not index), and the stack is rebuilt per group: an index id
                    // made the lazy stack keep the previous group's rows after switching groups.
                    LazyVStack(spacing: 1) {
                        ForEach(Array(channels.enumerated()), id: \.element.id) { idx, ch in
                            GuideRow(channel: ch, row: idx, start: start, end: end, pxPerSec: pxPerSec, layout: layout)
                        }
                    }
                    .id(model.selectedGroup)
                }
                .onChange(of: model.guideRow) { _, row in
                    guard channels.indices.contains(row) else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(channels[row].id, anchor: .center) }
                }
                .onChange(of: model.selectedGroup) { _, _ in
                    if let first = channels.first { proxy.scrollTo(first.id, anchor: .top) }
                }
                .onAppear {
                    if channels.indices.contains(model.guideRow) { proxy.scrollTo(channels[model.guideRow].id, anchor: .center) }
                }
            }
            .overlay(alignment: .topLeading) {
                // "Now" line.
                if model.now > start, model.now < end {
                    Rectangle().fill(Theme.live)
                        .frame(width: 2)
                        .offset(x: layout.channelColumn + model.now.timeIntervalSince(start) * pxPerSec)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(Theme.bg)
        .onScrollWheelHorizontal { dx in model.guideShift(slots: dx > 0 ? -1 : 1) }
    }
}

struct GuideRow: View {
    @EnvironmentObject var model: AppModel
    let channel: Channel
    let row: Int
    let start: Date
    let end: Date
    let pxPerSec: CGFloat
    let layout: GuideLayout

    var body: some View {
        let selectedRow = model.guideRow == row
        let isPlaying = model.playing?.channel.id == channel.id
        let fs = layout.fontScale
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                // Click/double-click area (kept apart from the star so the star always gets its clicks).
                HStack(spacing: 8) {
                    if model.library.settings.showChannelNumbers {
                        Text(verbatim: String(channel.number)).font(.system(size: 13 * fs).monospacedDigit()).foregroundStyle(Theme.dim)
                            .frame(minWidth: 30, alignment: .trailing)
                    }
                    ChannelLogo(url: channel.logo, size: min(30, layout.rowHeight * 0.55))
                    Text(channel.name).lineLimit(1).font(.system(size: 14 * fs, weight: selectedRow ? .semibold : .regular))
                    Spacer(minLength: 0)
                    if isPlaying { Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(Theme.accent) }
                    if channel.hasCatchup { Image(systemName: "clock.arrow.circlepath").font(.caption).foregroundStyle(Theme.faint) }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.play(channel) }
                .onTapGesture { model.guideRow = row; model.guideTime = model.now; model.play(channel, fullscreen: false) }
                FavouriteButton(channel: channel)
                    .font(.system(size: 13 * fs))
                    .frame(width: 22, height: layout.rowHeight)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 8).padding(.trailing, 4)
            .frame(width: layout.channelColumn, height: layout.rowHeight)
            .background(selectedRow ? Theme.cellLive : Theme.panel)
            .contextMenu {
                Button(model.library.isFavourite(channel) ? "Remove from Favourites" : "Add to Favourites") { model.library.toggleFavourite(channel) }
                Button("Play") { model.play(channel) }
                Button("Record now") { model.record(channel, model.library.programme(for: channel, at: model.now)) }
            }

            ZStack(alignment: .topLeading) {
                Theme.bg
                let progs = model.library.programmes(for: channel, in: start..<end)
                if progs.isEmpty {
                    cell(title: channel.name, subtitle: "No information", x: 0, width: (end.timeIntervalSince(start)) * pxPerSec,
                         focused: selectedRow, live: true, fs: fs)
                        .onTapGesture(count: 2) { model.play(channel) }
                        .onTapGesture { model.releaseTextFocus(); model.guideRow = row; model.guideTime = model.now; model.preview(channel) }
                    // Time cursor: ←/→ on a row without listings moves in 30-minute steps; show where it is.
                    if selectedRow, model.guideTime >= start, model.guideTime < end {
                        let slotStart = AppModel.slotFloor(model.guideTime)
                        Rectangle().fill(Theme.accent.opacity(0.35))
                            .frame(width: max(2, 1800 * pxPerSec - 2), height: layout.rowHeight)
                            .offset(x: max(0, slotStart.timeIntervalSince(start)) * pxPerSec)
                            .allowsHitTesting(false)
                    }
                }
                ForEach(progs) { p in
                    let x0 = max(p.start, start).timeIntervalSince(start) * pxPerSec
                    let x1 = min(p.stop, end).timeIntervalSince(start) * pxPerSec
                    let focused = selectedRow && p.start <= model.guideTime && model.guideTime < p.stop
                    let game = model.game(for: p, channel: channel)
                    cell(title: game.map { "\($0.away.abbreviation) @ \($0.home.abbreviation)" } ?? p.displayTitle,
                         subtitle: game.flatMap { g in g.scoreLine.map { "\($0) · \(g.detail)" } } ?? cellSubtitle(p),
                         x: x0, width: x1 - x0, focused: focused,
                         live: p.isLive(at: model.now), past: p.stop < model.now, catchup: channel.hasCatchup && p.stop < model.now,
                         recording: model.recorder.isScheduled(channel, p), reminder: model.recorder.hasReminder(channel, p),
                         event: p.kind == .sports, kindIcon: kindIcon(p), liveGame: game?.state == .live, fs: fs)
                        .onTapGesture(count: 2) {
                            model.guideRow = row; model.guideTime = p.start.addingTimeInterval(1); model.guideActivate()
                        }
                        .onTapGesture {
                            model.releaseTextFocus()
                            model.guideRow = row
                            model.guideTime = max(p.start, start).addingTimeInterval(1)
                            // What's on now plays in the preview; past/future programmes are just selected.
                            if p.isLive(at: model.now) { model.preview(channel) }
                        }
                        .contextMenu {
                            if p.isLive(at: model.now) { Button("Watch") { model.play(channel) } }
                            if p.stop > model.now { Button(model.recorder.isScheduled(channel, p) ? "Cancel recording" : "Record") { model.toggleRecord(channel, p) } }
                            if p.start > model.now {
                                Button(model.recorder.hasReminder(channel, p) ? "Remove reminder" : "Remind me") {
                                    if model.recorder.hasReminder(channel, p) { model.recorder.removeReminder(channel, p) } else { model.recorder.remind(channel, p) }
                                }
                            }
                        }
                }
            }
            .frame(height: layout.rowHeight)
            .clipped()
        }
        .onAppear { model.library.wantEPG(channel) }
    }

    /// "8:00 – 10:00 PM" plus "S2 E5" / "1993" so episodes and films read at a glance.
    private func cellSubtitle(_ p: Programme) -> String {
        var parts = [Theme.range(p)]
        if p.kind == .episode, let e = p.episodeLabel { parts.append(e) }
        if p.kind == .movie, let y = p.year { parts.append(String(y)) }
        if p.isNew { parts.append("New") }
        return parts.joined(separator: " · ")
    }

    private func kindIcon(_ p: Programme) -> String? {
        switch p.kind {
        case .movie: return "film"
        case .episode: return nil
        case .news: return "newspaper"
        default: return nil
        }
    }

    private func cell(title: String, subtitle: String, x: CGFloat, width: CGFloat, focused: Bool,
                      live: Bool, past: Bool = false, catchup: Bool = false, recording: Bool = false,
                      reminder: Bool = false, event: Bool = false, kindIcon: String? = nil, liveGame: Bool = false,
                      fs: CGFloat) -> some View {
        let dim = past && model.library.settings.dimPastProgrammes
        let twoLines = layout.rowHeight >= 46
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if recording { Circle().fill(Theme.live).frame(width: 8, height: 8) }
                if reminder { Image(systemName: "bell.fill").font(.caption2) }
                if liveGame { Circle().fill(Theme.live).frame(width: 7, height: 7) }
                if event { Image(systemName: "sportscourt").font(.caption2) }
                else if let kindIcon { Image(systemName: kindIcon).font(.caption2).opacity(0.8) }
                if catchup { Image(systemName: "clock.arrow.circlepath").font(.caption2) }
                Text(title).font(.system(size: 13 * fs, weight: .medium)).lineLimit(1)
            }
            if twoLines { Text(subtitle).font(.system(size: 11 * fs)).opacity(0.65).lineLimit(1) }
        }
        .padding(.horizontal, 8)
        .frame(width: max(0, width - 1), height: layout.rowHeight, alignment: .leading)
        .background(focused ? Theme.focus : (live ? Theme.cellLive : Theme.cell))
        .foregroundStyle(focused ? Theme.focusText : (dim ? Theme.dim.opacity(0.7) : Theme.text))
        .contentShape(Rectangle())
        .offset(x: x)
    }
}

// MARK: Horizontal scroll wheel / trackpad support

private struct HorizontalScrollModifier: ViewModifier {
    let action: (CGFloat) -> Void
    @State private var monitor: Any?
    @State private var accumulated: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
                    guard abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) else { return e }
                    accumulated += e.scrollingDeltaX
                    if abs(accumulated) > 60 {
                        action(accumulated)
                        accumulated = 0
                    }
                    return nil
                }
            }
            .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

extension View {
    func onScrollWheelHorizontal(_ action: @escaping (CGFloat) -> Void) -> some View {
        modifier(HorizontalScrollModifier(action: action))
    }
}

/// Mini-player controls over the guide's preview, shown on hover. Click = watch in the player, double-click = full screen.
struct PreviewControls: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var player: MPVController
    @State private var hover = ProcessInfo.processInfo.environment["MACTVMATE_FORCE_HOVER"] != nil

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.toggleFullScreen() }
                .onTapGesture { if model.playing != nil { model.screen = .player; model.flashInfoBar() } }

            if let target = model.playing {
                if let err = player.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.orange)
                        Text(err).font(.callout).multilineTextAlignment(.center)
                        Text(target.channel.name).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                        Button("Retry") { model.play(target.channel, fullscreen: false) }.controlSize(.small)
                    }
                    .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.75))
                } else if player.tuning {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.regular).tint(.white)
                        Text("Tuning \(target.channel.name)…").font(.callout).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
            if hover, let target = model.playing {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        if target.isLive { Badge(text: "LIVE", color: Theme.live) }
                        Text(target.channel.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer()
                        if player.isRecording { Label("REC", systemImage: "record.circle").font(.caption.weight(.bold)).foregroundStyle(Theme.live) }
                    }
                    .padding(10)
                    .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
                    Spacer()
                    HStack(spacing: 14) {
                        Button { player.togglePause() } label: { Image(systemName: player.isPaused ? "play.fill" : "pause.fill") }
                            .help("Play / pause (Space)")
                        Button { model.zap(-1) } label: { Image(systemName: "chevron.down") }.help("Channel down")
                        Button { model.zap(1) } label: { Image(systemName: "chevron.up") }.help("Channel up")
                        Button { player.isMuted.toggle() } label: { Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                        Slider(value: $player.volume, in: 0...130).frame(width: 90).controlSize(.mini)
                        Spacer()
                        Menu {
                            Section("Audio") {
                                ForEach(player.audioTracks) { t in
                                    Button { player.selectAudio(t.id) } label: { Text((t.selected ? "✓ " : "") + t.title) }
                                }
                            }
                            Section("Subtitles") {
                                Button("Off") { player.selectSubtitle(nil) }
                                ForEach(player.subtitleTracks) { t in
                                    Button { player.selectSubtitle(t.id) } label: { Text((t.selected ? "✓ " : "") + t.title) }
                                }
                            }
                        } label: { Image(systemName: "captions.bubble") }
                            .menuStyle(.borderlessButton).fixedSize()
                        Button { model.toggleRecording() } label: {
                            Image(systemName: player.isRecording ? "stop.circle.fill" : "record.circle")
                                .foregroundStyle(player.isRecording ? Theme.live : .white)
                        }
                        .help(player.isRecording ? "Stop recording" : "Record this channel")
                        Button { model.screen = .player; model.flashInfoBar() } label: { Image(systemName: "rectangle.expand.vertical") }
                            .help("Watch in the player")
                        Button { model.toggleFullScreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                            .help("Full screen")
                    }
                    .font(.system(size: 14))
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                }
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}
