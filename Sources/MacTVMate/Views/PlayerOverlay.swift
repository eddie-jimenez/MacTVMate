import SwiftUI

struct PlayerOverlay: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var player: MPVController
    @State private var hovering = false
    @State private var hoverTimer: Timer?

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
                .onTapGesture(count: 2) { model.toggleFullScreen() }
                .onTapGesture { model.showChannelList ? (model.showChannelList = false) : model.openChannelList() }
                .onContinuousHover { phase in
                    if case .active = phase { pokeHover() }
                }

            if player.isBuffering || player.tuning || (model.playing != nil && player.isIdle && player.errorMessage == nil) {
                ProgressView().controlSize(Theme.control(.large)).tint(.white)
            }
            if let err = player.errorMessage {
                VStack(spacing: Theme.s(8)) {
                    Image(systemName: "exclamationmark.triangle.fill").font(Theme.f(.largeTitle)).foregroundStyle(.orange)
                    Text(err)
                    Button("Retry") { if let p = model.playing { retry(p) } }
                }
                .padding(Theme.s(24))
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            }

            if model.showChannelList {
                ChannelListOverlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .transition(.move(edge: .leading))
            }

            if (model.showInfoBar || hovering || model.showControls) && !model.showChannelList {
                VStack(spacing: Theme.s(12)) {
                    TopControls(player: player).padding(Theme.s(16))
                    Spacer()
                    InfoBar(player: player)
                    if model.showControls { ControlsBar(player: player, form: model.controlsForm) }
                }
                .padding(.bottom, Theme.s(20))
                .transition(.opacity)
            }

            if player.isRecording {
                Label("REC", systemImage: "record.circle")
                    .font(Theme.f(.headline)).foregroundStyle(Theme.live)
                    .padding(Theme.s(8)).background(.black.opacity(0.6), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Theme.s(20))
            }
        }
        .onScrollWheelHorizontal { dx in
            guard model.playing?.isSeekable == true else { return }
            player.seek(relative: dx > 0 ? -10 : 10)
            model.flashInfoBar()
        }
        .animation(.easeInOut(duration: 0.18), value: model.showChannelList)
        .animation(.easeInOut(duration: 0.25), value: model.showInfoBar || hovering)
    }

    private func pokeHover() {
        hovering = true
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            Task { @MainActor in
                hovering = false
                // Keep the picture clean in full screen; the cursor reappears on any mouse move.
                if model.isFullScreen { NSCursor.setHiddenUntilMouseMoves(true) }
            }
        }
    }

    private func retry(_ p: PlaybackTarget) {
        switch p {
        case .live(let c): model.play(c)
        case .catchup(let c, let prog): model.playCatchup(c, prog)
        case .vod(let c, let key): model.playVOD(title: c.name, url: c.url, poster: c.logo, key: key, group: c.group)
        }
    }
}

struct TopControls: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var player: MPVController

    var body: some View {
        HStack(spacing: Theme.s(14)) {
            Button { model.showGuide() } label: { Label("Guide", systemImage: "list.bullet.rectangle") }
            Button { model.openChannelList() } label: { Label("Channels", systemImage: "list.number") }
            Button { model.openSearch() } label: { Label("Search", systemImage: "magnifyingglass") }
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
                Image(systemName: player.isRecording ? "stop.circle.fill" : "record.circle").foregroundStyle(player.isRecording ? Theme.live : .white)
            }
            .help("Record (R)")
            Button { player.isMuted.toggle() } label: { Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
            Slider(value: $player.volume, in: 0...130).frame(width: Theme.s(110))
            Button { model.toggleFullScreen() } label: {
                Label(model.isFullScreen ? "Exit Full Screen" : "Full Screen",
                      systemImage: model.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .help("Full screen (F or ⌘↩)")
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, Theme.s(14)).padding(.vertical, Theme.s(8))
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct InfoBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var player: MPVController

    var body: some View {
        if let target = model.playing {
            let ch = target.channel
            let current: Programme? = {
                if case .catchup(_, let p) = target { return p }
                return model.library.programme(for: ch, at: model.now)
            }()
            let next = current.flatMap { model.library.programme(for: ch, at: $0.stop.addingTimeInterval(1)) }

            HStack(alignment: .top, spacing: Theme.s(18)) {
                ChannelLogo(url: ch.logo, size: 56)
                VStack(alignment: .leading, spacing: Theme.s(6)) {
                    HStack(spacing: Theme.s(8)) {
                        if ch.number > 0 { Text(verbatim: String(ch.number)).font(Theme.f(.title3).monospacedDigit()).foregroundStyle(Theme.dim) }
                        Text(ch.name).font(Theme.f(.title3).weight(.semibold)).lineLimit(1)
                        if target.isLive { FavouriteButton(channel: ch) }
                        switch target {
                        case .catchup: Badge(text: "CATCH-UP")
                        case .vod(let c, _): Badge(text: c.group.uppercased(), color: .purple)
                        case .live: Badge(text: "LIVE", color: Theme.live)
                        }
                        if player.videoSize.height > 0 { Badge(text: resolutionLabel(player.videoSize), color: .gray) }
                        Spacer()
                        Text(Theme.time.string(from: model.now)).font(Theme.f(.title3).monospacedDigit())
                    }
                    if case .vod = target {
                        if player.duration > 0 { ScrubBar(player: player) }
                    } else if let p = current, let game = model.game(for: p, channel: ch) {
                        GameHeader(game: game)
                        ProgressLine(value: p.progress(at: model.now))
                    } else if let p = current {
                        HStack {
                            Text(p.displayTitle).font(Theme.f(.title2).weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(Theme.range(p)).foregroundStyle(Theme.dim)
                        }
                        if target.isSeekable, player.duration > 0 {
                            ScrubBar(player: player)
                        } else {
                            ProgressLine(value: p.progress(at: model.now))
                        }
                        if let desc = p.desc { Text(desc).font(Theme.f(.callout)).foregroundStyle(Theme.dim).lineLimit(2) }
                    } else {
                        Text("No programme information").foregroundStyle(Theme.dim)
                    }
                    if let next {
                        Text("Next: \(Theme.time.string(from: next.start))  \(next.title)").font(Theme.f(.callout)).foregroundStyle(Theme.faint)
                    }
                }
            }
            .padding(Theme.s(18))
            .frame(maxWidth: Theme.s(1100))
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func resolutionLabel(_ s: CGSize) -> String {
        switch s.height {
        case 2000...: return "4K"
        case 1000...: return "FHD"
        case 700...: return "HD"
        default: return "SD"
        }
    }

    private func fmt(_ t: Double) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct ChannelListOverlay: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: Theme.s(0)) {
            // Groups
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.s(2)) {
                        ForEach(Array(model.library.groups.enumerated()), id: \.element.id) { i, g in
                            let focused = model.channelListFocusGroups && i == model.listGroupSelection
                            HStack {
                                Text(g.name).lineLimit(1)
                                Spacer()
                                Text("\(g.count)").foregroundStyle(focused ? Theme.focusText.opacity(0.6) : Theme.faint).font(Theme.f(.caption))
                            }
                            .padding(.horizontal, Theme.s(12)).padding(.vertical, Theme.s(8))
                            .background(focused ? Theme.focus : (g.name == model.selectedGroup ? Theme.cellLive : .clear), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(focused ? Theme.focusText : Theme.text)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedGroup = g.name
                                model.listGroupSelection = i
                                model.listSelection = 0
                                model.channelListFocusGroups = false
                            }
                            .id(i)
                        }
                    }
                    .padding(Theme.s(8))
                }
                .onChange(of: model.listGroupSelection) { _, i in proxy.scrollTo(i, anchor: .center) }
            }
            .frame(width: Theme.s(230))
            .background(Theme.bg)

            // Channels
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.s(2)) {
                        ForEach(Array(model.groupChannels.enumerated()), id: \.element.id) { i, ch in
                            ChannelListRow(channel: ch, focused: !model.channelListFocusGroups && i == model.listSelection)
                                .onTapGesture(count: 2) { model.play(ch); model.showChannelList = false }
                                .onTapGesture { model.listSelection = i; model.channelListFocusGroups = false; model.play(ch) }
                                .contextMenu {
                                    Button(model.library.isFavourite(ch) ? "Remove from Favourites" : "Add to Favourites") { model.library.toggleFavourite(ch) }
                                }
                        }
                    }
                    .padding(Theme.s(8))
                    .id(model.selectedGroup)
                }
                .onChange(of: model.listSelection) { _, i in
                    let list = model.groupChannels
                    if list.indices.contains(i) { proxy.scrollTo(list[i].id, anchor: .center) }
                }
                .onAppear {
                    let list = model.groupChannels
                    if list.indices.contains(model.listSelection) { proxy.scrollTo(list[model.listSelection].id, anchor: .center) }
                }
            }
            .frame(width: Theme.s(440))
            .background(Theme.panel)
        }
    }
}

struct ChannelListRow: View {
    @EnvironmentObject var model: AppModel
    let channel: Channel
    let focused: Bool

    var body: some View {
        let p = model.library.programme(for: channel, at: model.now)
        let isPlaying = model.playing?.channel.id == channel.id
        HStack(spacing: Theme.s(10)) {
            Text(verbatim: String(channel.number)).font(Theme.f(.callout).monospacedDigit()).frame(width: Theme.s(40), alignment: .trailing).opacity(0.6)
            ChannelLogo(url: channel.logo, size: 30)
            VStack(alignment: .leading, spacing: Theme.s(3)) {
                HStack(spacing: Theme.s(6)) {
                    Text(channel.name).font(.system(size: Theme.uiScale * 14, weight: .semibold)).lineLimit(1)
                    if isPlaying { Image(systemName: "speaker.wave.2.fill").font(Theme.f(.caption2)).foregroundStyle(focused ? Theme.focusText : Theme.accent) }
                }
                Text(p?.title ?? "No information").font(Theme.f(.caption)).lineLimit(1).opacity(0.7)
                if let p { ProgressLine(value: p.progress(at: model.now), color: focused ? .black.opacity(0.6) : Theme.accent) }
            }
            FavouriteButton(channel: channel, inverted: focused)
        }
        .padding(.horizontal, Theme.s(10)).padding(.vertical, Theme.s(7))
        .background(focused ? Theme.focus : .clear, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(focused ? Theme.focusText : Theme.text)
        .contentShape(Rectangle())
        .onAppear { model.library.wantEPG(channel) }
    }
}

/// Draggable timeline for movies, episodes, catch-up and recordings: drag or click to jump.
struct ScrubBar: View {
    @ObservedObject var player: MPVController
    @State private var dragFraction: Double?
    @State private var hoverFraction: Double?

    var body: some View {
        let dur = max(player.duration, 1)
        let frac = dragFraction ?? min(1, max(0, player.position / dur))
        VStack(spacing: Theme.s(6)) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22)).frame(height: dragFraction != nil ? 8 : 6)
                    Capsule().fill(Theme.accent).frame(width: max(0, w * frac), height: dragFraction != nil ? 8 : 6)
                    Circle().fill(.white).frame(width: Theme.s(16), height: Theme.s(16)).shadow(radius: 3)
                        .offset(x: w * frac - 8)
                    if let f = dragFraction ?? hoverFraction {
                        Text(Self.fmt(f * dur))
                            .font(Theme.f(.caption).monospacedDigit().weight(.semibold))
                            .padding(.horizontal, Theme.s(6)).padding(.vertical, Theme.s(3))
                            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                            .offset(x: min(max(0, w * f - 28), w - 56), y: -24)
                    }
                }
                .frame(height: Theme.s(24))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in dragFraction = min(1, max(0, v.location.x / w)) }
                    .onEnded { v in
                        let f = min(1, max(0, v.location.x / w))
                        player.seek(absolute: f * dur)
                        // Hold the thumb where it was dropped until mpv reports the new position.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dragFraction = nil }
                    })
                .onContinuousHover { phase in
                    if case .active(let p) = phase { hoverFraction = min(1, max(0, p.x / w)) } else { hoverFraction = nil }
                }
            }
            .frame(height: Theme.s(24))
            HStack {
                Text(Self.fmt(frac * dur))
                Spacer()
                Text("←/→ 30 s · swipe 10 s · Space pause").foregroundStyle(Theme.faint)
                Spacer()
                Text("-" + Self.fmt(max(0, dur - frac * dur)))
            }
            .font(Theme.f(.caption).monospacedDigit())
            .foregroundStyle(Theme.dim)
        }
    }

    static func fmt(_ t: Double) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Remote-friendly playback controls (Menu on live TV, OK on movies and catch-up). ← → move, OK presses.
struct ControlsBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var player: MPVController
    @ObservedObject var form: FocusForm

    private struct Item: Identifiable {
        let id: String
        let title: String
        let icon: String
        var tint: Color? = nil
        let run: () -> Void
    }

    var body: some View {
        let items = self.items
        HStack(spacing: Theme.s(10)) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                VStack(spacing: Theme.s(6)) {
                    Image(systemName: item.icon).font(.system(size: Theme.uiScale * 22, weight: .semibold))
                        .foregroundStyle(item.tint ?? Theme.text)
                    Text(item.title).font(Theme.f(.caption)).lineLimit(1)
                }
                .frame(width: Theme.s(96), height: Theme.s(70))
                .background(form.engaged && form.spot.col == i ? Theme.accent.opacity(0.35) : Color.black.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture { model.pokeControls(); item.run() }
                .focusSpot(form, row: 0, col: i, owner: item.id, radius: 12) { item.run() }
            }
        }
        .padding(Theme.s(10))
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private var items: [Item] {
        guard let target = model.playing else { return [] }
        var list: [Item] = []
        if target.isSeekable {
            list.append(Item(id: "back", title: "−30 s", icon: "gobackward.30") { player.seek(relative: -30) })
            list.append(Item(id: "pause", title: player.isPaused ? "Play" : "Pause", icon: player.isPaused ? "play.fill" : "pause.fill") { player.togglePause() })
            list.append(Item(id: "fwd", title: "+30 s", icon: "goforward.30") { player.seek(relative: 30) })
            list.append(Item(id: "start", title: "Start over", icon: "backward.end.fill") { player.seek(absolute: 0) })
        } else {
            let ch = target.channel
            let fav = model.library.isFavourite(ch)
            list.append(Item(id: "channels", title: "Channels", icon: "list.number") { model.hideControls(); model.openChannelList() })
            list.append(Item(id: "pause", title: player.isPaused ? "Play" : "Pause", icon: player.isPaused ? "play.fill" : "pause.fill") { player.togglePause() })
            list.append(Item(id: "fav", title: fav ? "Favourite" : "Add favourite", icon: fav ? "star.fill" : "star", tint: fav ? .yellow : nil) {
                model.library.toggleFavourite(ch)
            })
            list.append(Item(id: "rec", title: player.isRecording ? "Stop rec" : "Record", icon: player.isRecording ? "stop.circle.fill" : "record.circle",
                             tint: player.isRecording ? Theme.live : nil) { model.toggleRecording() })
            list.append(Item(id: "last", title: "Last channel", icon: "arrow.uturn.backward") { model.playPrevious() })
        }
        list.append(Item(id: "tracks", title: "Audio & subs", icon: "captions.bubble") { showTracks() })
        list.append(Item(id: "mute", title: player.isMuted ? "Unmute" : "Mute", icon: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
            player.isMuted.toggle()
        })
        list.append(Item(id: "guide", title: "Guide", icon: "list.bullet.rectangle") { model.hideControls(); model.showGuide() })
        list.append(Item(id: "fs", title: model.isFullScreen ? "Exit full" : "Full screen",
                         icon: model.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
            model.toggleFullScreen()
        })
        return list
    }

    private func showTracks() {
        var a: [MenuAction] = player.audioTracks.map { t in
            MenuAction(title: (t.selected ? "✓ " : "") + "Audio: " + t.title, icon: "speaker.wave.2") { player.selectAudio(t.id) }
        }
        a.append(MenuAction(title: (player.subtitleTracks.contains { $0.selected } ? "" : "✓ ") + "Subtitles off", icon: "captions.bubble") {
            player.selectSubtitle(nil)
        })
        a += player.subtitleTracks.map { t in
            MenuAction(title: (t.selected ? "✓ " : "") + "Subtitles: " + t.title, icon: "captions.bubble.fill") { player.selectSubtitle(t.id) }
        }
        model.showOptions("Audio & subtitles", a)
    }
}
