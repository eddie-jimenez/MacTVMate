import AppKit
import Combine
import SwiftUI

/// Main sections, matching TiViMate's sidebar. Settings is a panel over whichever screen is showing.
enum Screen: Equatable {
    case guide
    case player
    case movies
    case shows
    case recordings
    case myList

    var isBrowser: Bool { [.movies, .shows, .recordings, .myList].contains(self) }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", playlists = "Playlists", epg = "EPG", groups = "Groups",
         appearance = "Appearance", playback = "Playback", keyboard = "Remote & keyboard", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .playlists: return "list.bullet.rectangle"
        case .epg: return "calendar"
        case .groups: return "square.stack.3d.up"
        case .appearance: return "paintpalette"
        case .playback: return "play.rectangle"
        case .keyboard: return "appletvremote.gen4"
        case .about: return "info.circle"
        }
    }
}

/// UI state + playback coordination + keyboard handling.
@MainActor
final class AppModel: ObservableObject {
    let library = Library()
    let player = MPVController()
    let vod: VODStore
    let recorder: Recorder
    let sports = SportsData()
    let meta = MetaStore()
    let remote = RemoteControl()
    private(set) var webRemote: WebRemote!

    @Published var screen: Screen = .guide {
        didSet { screenChanged(from: oldValue) }
    }
    @Published var showSettings = false
    /// Settings, bindable from views (`$model.settings.x`).
    var settings: AppSettings {
        get { library.settings }
        set { library.settings = newValue }
    }
    @Published var settingsSection: SettingsSection = .general
    /// Live channel paused while browsing Movies/Shows, resumed on return to TV.
    private var suspendedLive: Channel?
    @Published var selectedGroup: String = ChannelGroup.all
    @Published private(set) var playing: PlaybackTarget?
    @Published private(set) var previousChannel: Channel?

    // Player overlays
    @Published var showInfoBar = false
    @Published var showChannelList = false
    @Published var channelListFocusGroups = false
    @Published var listSelection: Int = 0
    @Published var listGroupSelection: Int = 0
    @Published var numberEntry: String = ""
    @Published var showSearch = false
    @Published private(set) var isFullScreen = false
    @Published var searchQuery = ""

    // Guide
    @Published var guideRow: Int = 0
    @Published var guideTime: Date = .now
    @Published var guideStart: Date = AppModel.slotFloor(.now)
    @Published var previewInGuide = true

    @Published var now: Date = .now

    private var infoTimer: Timer?
    private var numberTimer: Timer?
    private var previewTask: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()
    private var keyMonitor: Any?

    static let slot: TimeInterval = 30 * 60

    init() {
        vod = VODStore(library: library)
        recorder = Recorder(library: library)
        library.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        vod.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        recorder.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        sports.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        meta.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        remote.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        remote.handler = { [weak self] action in self?.remoteAction(action) }
        webRemote = WebRemote(model: self)
        webRemote.start()
        webRemote.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        // Make sure the remote key is persisted from the first launch.
        if library.settings.remoteToken.isEmpty { library.settings.remoteToken = AppSettings.newToken() } else { library.save() }
        // Keep Control Center / Now Playing in sync with playback.
        player.$isPaused.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateNowPlaying() }
        }.store(in: &bag)
        $playing.sink { [weak self] _ in DispatchQueue.main.async { self?.updateNowPlaying() } }.store(in: &bag)
        library.$settings.removeDuplicates().sink { [weak self] s in
            Theme.accent = s.accentColor
            self?.player.apply(s)
        }.store(in: &bag)
        // Remember where movies/episodes were left.
        Timer.publish(every: 10, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.saveVODPosition()
            self?.updateNowPlaying()
        }.store(in: &bag)
        Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] d in self?.now = d }.store(in: &bag)
        NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)
            .sink { [weak self] _ in self?.isFullScreen = true }.store(in: &bag)
        NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)
            .sink { [weak self] _ in self?.isFullScreen = false }.store(in: &bag)
        if library.sources.isEmpty { settingsSection = .playlists; showSettings = true }
        installKeyMonitor()
        Task { await reload() }
        DebugSnapshots.runIfRequested(self)
    }

    static func slotFloor(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / slot).rounded(.down) * slot)
    }

    func reload(force: Bool = false) async {
        await library.reload(force: force)
        if !library.groups.contains(where: { $0.name == selectedGroup }) { selectedGroup = ChannelGroup.all }
        if playing == nil, library.settings.startOnLastChannel,
           let last = library.recents.first, let ch = library.channels.first(where: { $0.id == last }) {
            play(ch, fullscreen: false)
        }
        // After resuming playback so the focused row is the channel that's playing.
        resetGuideToNow()
    }

    // MARK: Lists

    var groupChannels: [Channel] { library.channels(in: selectedGroup) }

    var xtreamClient: XtreamClient? {
        guard let s = library.activeSource, case let .xtream(server, u, p) = s.kind else { return nil }
        return XtreamClient(server: server, username: u, password: p, userAgent: s.userAgent)
    }

    // MARK: Playback

    func play(_ channel: Channel, fullscreen: Bool = true) {
        saveVODPosition()
        suspendedLive = nil
        if let current = playing, current.isLive, current.channel.id != channel.id { previousChannel = current.channel }
        playing = .live(channel)
        player.load(channel.url, userAgent: userAgent(for: channel), referrer: channel.referrer)
        library.noteWatched(channel)
        library.wantEPG(channel)
        if fullscreen { screen = .player }
        flashInfoBar()
    }

    /// Plays a live channel in the guide's preview (no-op if it's already the one playing).
    func preview(_ channel: Channel) {
        if case .live(let c)? = playing, c.id == channel.id, !player.isIdle { return }
        play(channel, fullscreen: false)
    }

    func playCatchup(_ channel: Channel, _ programme: Programme) {
        saveVODPosition()
        guard let url = Catchup.url(for: channel, programme: programme, xtream: xtreamClient, serverTimeZone: library.xtreamTimeZone) else { return }
        if let current = playing?.channel, current.id != channel.id { previousChannel = current }
        playing = .catchup(channel, programme)
        player.load(url, userAgent: userAgent(for: channel), referrer: channel.referrer, isLive: false)
        screen = .player
        flashInfoBar()
    }

    private func userAgent(for channel: Channel) -> String {
        channel.userAgent ?? library.activeSource?.userAgent ?? ""
    }

    /// Plays a movie or episode, resuming where it was left.
    func playVOD(title: String, url: URL, poster: URL?, key: String, group: String) {
        saveVODPosition()
        suspendedLive = nil
        let pseudo = Channel(id: key, number: 0, name: title, group: group, logo: poster, url: url)
        playing = .vod(pseudo, key: key)
        player.load(url, userAgent: library.activeSource?.userAgent ?? "", isLive: false, startAt: library.positions[key])
        screen = .player
        flashInfoBar()
    }

    func saveVODPosition() {
        guard case .vod(_, let key)? = playing, player.duration > 0 else { return }
        library.savePosition(key, player.position, duration: player.duration)
    }

    /// The game a sports programme shows. "Upcoming: …" lead-in blocks resolve to the event that follows them.
    func game(for p: Programme, channel: Channel) -> Game? {
        if p.isEvent, p.title.hasPrefix("Upcoming: "),
           let event = library.programmes(for: channel).first(where: { $0.isEvent && !$0.title.hasPrefix("Upcoming: ") }) {
            return sports.game(for: event, channel: channel)
        }
        return sports.game(for: p, channel: channel)
    }

    /// Record from the guide: future programmes are scheduled, the current one records until it ends.
    func record(_ channel: Channel, _ p: Programme?) {
        let ua = userAgent(for: channel)
        if let p, p.start > now { recorder.schedule(channel, p, userAgent: ua) }
        else { recorder.recordNow(channel, programme: p, userAgent: ua) }
    }

    func toggleRecord(_ channel: Channel, _ p: Programme) {
        if let r = recorder.recording(for: channel, p), r.status == .scheduled || r.status == .recording { recorder.cancel(r) }
        else { record(channel, p) }
    }

    private func screenChanged(from old: Screen) {
        guard old != screen else { return }
        if screen.isBrowser, case .live(let c)? = playing {
            // Like TiViMate, the live preview stops while browsing Movies/Shows.
            suspendedLive = c
            player.stop()
        } else if screen == .guide, let c = suspendedLive {
            suspendedLive = nil
            play(c, fullscreen: false)
        }
        if screen.isBrowser, case .vod? = playing { saveVODPosition(); player.stop(); playing = nil }
    }

    func zap(_ delta: Int) {
        let list = groupChannels.isEmpty ? library.channels : groupChannels
        guard !list.isEmpty else { return }
        let idx = playing.flatMap { p in list.firstIndex { $0.id == p.channel.id } } ?? 0
        play(list[(idx + delta + list.count) % list.count], fullscreen: screen == .player)
    }

    func playPrevious() {
        if let p = previousChannel { play(p, fullscreen: screen == .player) }
    }

    func toggleRecording() {
        guard let target = playing else { return }
        if player.isRecording { player.stopRecording(); return }
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("MacTVMate")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        let title = library.programme(for: target.channel)?.title ?? target.channel.name
        let safe = "\(target.channel.name) - \(title)".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        player.startRecording(to: dir.appendingPathComponent("\(safe) \(f.string(from: .now)).ts"))
    }

    /// Full screen always shows the video: from the guide it switches to the player first.
    func toggleFullScreen() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        if !window.styleMask.contains(.fullScreen), playing != nil {
            screen = .player
            showChannelList = false
            showSearch = false
        }
        window.toggleFullScreen(nil)
    }

    func openSearch() {
        showChannelList = false
        showSearch = true
    }

    func flashInfoBar() {
        showInfoBar = true
        infoTimer?.invalidate()
        infoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.showInfoBar = false }
        }
    }

    func openChannelList() {
        let list = groupChannels
        listSelection = playing.flatMap { p in list.firstIndex { $0.id == p.channel.id } } ?? 0
        listGroupSelection = library.groups.firstIndex { $0.name == selectedGroup } ?? 0
        channelListFocusGroups = false
        showChannelList = true
        showInfoBar = false
    }

    func showGuide() {
        showChannelList = false
        resetGuideToNow()
        screen = .guide
    }

    func resetGuideToNow() {
        guideStart = Self.slotFloor(.now)
        guideTime = .now
        let list = groupChannels
        guideRow = playing.flatMap { p in list.firstIndex { $0.id == p.channel.id } } ?? min(guideRow, max(0, list.count - 1))
    }

    // MARK: Guide navigation

    var guideSelectedChannel: Channel? {
        let list = groupChannels
        return list.indices.contains(guideRow) ? list[guideRow] : nil
    }

    var guideSelectedProgramme: Programme? {
        guideSelectedChannel.flatMap { library.programme(for: $0, at: guideTime) }
    }

    func guideMove(rows: Int) {
        let count = groupChannels.count
        guard count > 0 else { return }
        guideRow = min(count - 1, max(0, guideRow + rows))
        schedulePreview()
    }

    func guideMove(programmes delta: Int) {
        guard let ch = guideSelectedChannel else { return }
        if let p = library.programme(for: ch, at: guideTime) {
            let list = library.programmes(for: ch)
            if let i = list.firstIndex(of: p), list.indices.contains(i + delta) {
                let next = list[i + delta]
                guideTime = next.start.addingTimeInterval(1)
            } else {
                guideTime = guideTime.addingTimeInterval(Double(delta) * Self.slot)
            }
        } else {
            guideTime = guideTime.addingTimeInterval(Double(delta) * Self.slot)
        }
        keepGuideTimeVisible()
    }

    func guideShift(slots: Int) {
        guideStart = guideStart.addingTimeInterval(Double(slots) * Self.slot)
        guideTime = guideTime.addingTimeInterval(Double(slots) * Self.slot)
    }

    var guideVisibleSpan: TimeInterval = 2 * 3600

    private func keepGuideTimeVisible() {
        if guideTime < guideStart { guideStart = Self.slotFloor(guideTime) }
        if guideTime >= guideStart.addingTimeInterval(guideVisibleSpan) {
            guideStart = Self.slotFloor(guideTime).addingTimeInterval(-guideVisibleSpan + Self.slot * 2)
        }
    }

    func guideActivate() {
        guard let ch = guideSelectedChannel else { return }
        if let p = guideSelectedProgramme, p.stop < .now, ch.hasCatchup {
            playCatchup(ch, p)
        } else if let p = guideSelectedProgramme, p.start > .now {
            // Future programme: nothing to play yet.
            NSSound.beep()
        } else if case .live(let c)? = playing, c.id == ch.id {
            screen = .player
            flashInfoBar()
        } else {
            play(ch)
        }
    }

    private func schedulePreview() {
        guard previewInGuide, screen == .guide else { return }
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, let ch = self.guideSelectedChannel else { return }
            if case .live(let c)? = self.playing, c.id == ch.id { return }
            self.play(ch, fullscreen: false)
        }
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Let text fields handle their own typing.
            if let responder = event.window?.firstResponder, responder is NSTextView { return event }
            return MainActor.assumeIsolated { self.handleKey(event) } ? nil : event
        }
    }

    // MARK: Remote control

    /// Shield remote (and other remotes): D-pad/OK/Back are replayed as real key presses, so they behave exactly like
    /// the keyboard everywhere — guide, player, Movies sheets, Settings. Home/Menu/media buttons map to TiViMate's actions.
    func remoteAction(_ a: RemoteControl.Action) {
        func key(_ code: UInt16, _ chars: String) {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
                  let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: chars,
                                            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) else { return }
            NSApp.postEvent(ev, atStart: false)
        }
        let live = playing?.isLive ?? true
        switch a {
        case .back: key(53, "\u{1b}")
        case .ok: key(36, "\r")
        case .up: key(126, "\u{F700}")
        case .down: key(125, "\u{F701}")
        case .left: key(123, "\u{F702}")
        case .right: key(124, "\u{F703}")
        case .home:
            // TiViMate's Home: back to the TV guide from anywhere.
            showSearch = false; showSettings = false; showChannelList = false
            showGuide()
        case .menu:
            // Menu: from the player, the channel list; elsewhere, Settings.
            if screen == .player, !showChannelList { openChannelList() } else { showSettings.toggle() }
        case .playPause: player.togglePause()
        case .play: if player.isPaused { player.togglePause() }
        case .pause: if !player.isPaused { player.togglePause() }
        case .channelUp: if live { zap(1) } else { player.seek(relative: 30) }
        case .channelDown: if live { zap(-1) } else { player.seek(relative: -30) }
        case .seekForward: if live { zap(1) } else { player.seek(relative: 30) }
        case .seekBackward: if live { zap(-1) } else { player.seek(relative: -30) }
        }
    }

    // MARK: iPhone remote API

    func webAction(_ a: String, value: Any?) {
        switch a {
        case "up": remoteAction(.up)
        case "down": remoteAction(.down)
        case "left": remoteAction(.left)
        case "right": remoteAction(.right)
        case "ok": remoteAction(.ok)
        case "back": remoteAction(.back)
        case "home": remoteAction(.home)
        case "menu": remoteAction(.menu)
        case "playPause": remoteAction(.playPause)
        case "chUp": remoteAction(.channelUp)
        case "chDown": remoteAction(.channelDown)
        case "seekFwd": remoteAction(.seekForward)
        case "seekBack": remoteAction(.seekBackward)
        case "volUp": player.volume = min(130, player.volume + 5)
        case "volDown": player.volume = max(0, player.volume - 5)
        case "mute": player.isMuted.toggle()
        case "fullscreen": toggleFullScreen()
        case "info": flashInfoBar()
        case "record": toggleRecording()
        case "last": playPrevious()
        case "guide": showSettings = false; showSearch = false; showGuide()
        case "digit": if let d = (value as? Int) ?? Int("\(value ?? "")") { enterDigit(d) }
        default: break
        }
    }

    func remoteState() -> [String: Any] {
        var s: [String: Any] = ["screen": "\(screen)", "volume": Int(player.volume), "muted": player.isMuted,
                                "recording": player.isRecording]
        guard let target = playing else { return s }
        let ch = target.channel
        var np: [String: Any] = ["channel": ch.name, "number": ch.number, "logo": ch.logo?.absoluteString ?? "",
                                  "live": target.isLive, "paused": player.isPaused,
                                  "position": player.position, "duration": player.duration]
        var programme: Programme?
        if case .catchup(_, let p) = target { programme = p } else if target.isLive { programme = library.programme(for: ch, at: now) }
        if let p = programme {
            np["title"] = p.displayTitle
            np["time"] = Theme.range(p)
            np["progress"] = p.progress(at: now)
            np["art"] = meta.art(for: p)?.absoluteString ?? ""
            if let g = game(for: p, channel: ch) {
                np["score"] = g.scoreLine ?? "\(g.away.abbreviation) @ \(g.home.abbreviation)"
                np["detail"] = g.detail
            } else if let t = meta.imdb(for: p) {
                np["detail"] = "IMDb \(t.ratingText)" + (t.year.map { " · \($0)" } ?? "")
            }
        } else {
            np["title"] = ch.name
        }
        s["playing"] = np
        return s
    }

    func remoteChannels(group: String) -> [String: Any] {
        let list = library.channels(in: group).prefix(400).map { c -> [String: Any] in
            var row: [String: Any] = ["id": c.id, "number": c.number, "name": c.name, "logo": c.logo?.absoluteString ?? ""]
            if let p = library.programme(for: c, at: now) {
                row["title"] = p.displayTitle
                row["time"] = Theme.range(p)
                row["progress"] = p.progress(at: now)
                if let g = game(for: p, channel: c), let line = g.scoreLine { row["score"] = "\(line) · \(g.detail)" }
            }
            row["playing"] = playing?.channel.id == c.id
            return row
        }
        return ["group": group, "channels": Array(list)]
    }

    func remoteSearch(_ q: String) -> [String: Any] {
        let r = search(q, limit: 40)
        func row(_ x: SearchResult) -> [String: Any] {
            var d: [String: Any] = ["id": x.channel.id, "number": x.channel.number, "name": x.channel.name,
                                    "logo": x.channel.logo?.absoluteString ?? ""]
            if let p = x.programme { d["title"] = p.displayTitle; d["time"] = Theme.dayLabel(p.start, withTime: true)
                d["live"] = p.isLive(at: now) }
            else { d["title"] = library.programme(for: x.channel, at: now)?.displayTitle ?? "" }
            return d
        }
        return ["channels": r.channels.map(row), "programmes": r.programmes.map(row)]
    }

    func remotePlay(id: String) {
        guard let c = library.channels.first(where: { $0.id == id }) else { return }
        showSearch = false; showSettings = false
        play(c)
    }

    func updateNowPlaying() {
        guard let target = playing else {
            remote.updateNowPlaying(title: nil, subtitle: nil, art: nil, duration: 0, position: 0, paused: true, live: true)
            return
        }
        let ch = target.channel
        var title = ch.name, subtitle: String? = nil, art = ch.logo
        switch target {
        case .live(let c):
            if let p = library.programme(for: c, at: now) {
                if let g = game(for: p, channel: c) {
                    title = g.scoreLine.map { "\($0) · \(g.detail)" } ?? "\(g.away.short) @ \(g.home.short)"
                } else {
                    title = p.displayTitle
                    art = meta.art(for: p) ?? art
                }
                subtitle = c.name
            }
        case .catchup(let c, let p):
            title = p.displayTitle; subtitle = "\(c.name) · catch-up"; art = meta.art(for: p) ?? art
        case .vod(let c, _):
            title = c.name; subtitle = c.group
        }
        remote.updateNowPlaying(title: title, subtitle: subtitle, art: art, duration: player.duration,
                                position: player.position, paused: player.isPaused, live: target.isLive)
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        if remote.testing { remote.logKey(e, action: nil) }
        if e.modifierFlags.contains(.command) { return false }
        let chars = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if showSearch {
            if e.keyCode == 53 { showSearch = false; return true }
            return false
        }
        if showSettings {
            if e.keyCode == 53, !library.sources.isEmpty { showSettings = false; return true }
            return false
        }
        if chars == "/" { openSearch(); return true }

        if let digit = Int(chars), chars.count == 1, !screen.isBrowser {
            enterDigit(digit)
            return true
        }

        switch screen {
        case .movies, .shows, .recordings, .myList:
            if e.keyCode == 53 { screen = .guide; return true }
            return false
        case .guide:
            return handleGuideKey(e, chars)
        case .player:
            return handlePlayerKey(e, chars)
        }
    }

    private func handleGuideKey(_ e: NSEvent, _ chars: String) -> Bool {
        switch e.keyCode {
        // ↑/↓ are channel up/down (44 → 45 / 44 → 43) unless set to follow the screen.
        case 126: guideMove(rows: library.settings.guideArrowsFollowChannelNumbers ? 1 : -1)   // up
        case 125: guideMove(rows: library.settings.guideArrowsFollowChannelNumbers ? -1 : 1)   // down
        case 123: guideMove(programmes: -1)          // left
        case 124: guideMove(programmes: 1)           // right
        case 116: guideMove(rows: -8)                // page up
        case 121: guideMove(rows: 8)                 // page down
        case 36, 76: guideActivate()                 // return / enter
        case 53, 51:                                 // esc / backspace
            if playing != nil { screen = .player; flashInfoBar() }
        default:
            switch chars {
            case "f": if let ch = guideSelectedChannel { library.toggleFavourite(ch) }
            case "n": resetGuideToNow()
            case "g": if playing != nil { screen = .player }
            default: return false
            }
        }
        return true
    }

    private func handlePlayerKey(_ e: NSEvent, _ chars: String) -> Bool {
        if showChannelList { return handleListKey(e) }
        let isCatchup = playing?.isSeekable ?? false   // catch-up, movies, episodes, recordings
        switch e.keyCode {
        case 126, 116: zap(1)                        // up / page up
        case 125, 121: zap(-1)                       // down / page down
        case 123: if isCatchup { player.seek(relative: -30) } else { openChannelList() }
        case 124: if isCatchup { player.seek(relative: 30) } else { flashInfoBar() }
        case 36, 76: openChannelList()
        case 53:                                     // esc: info bar, then full screen, then guide
            if showInfoBar { showInfoBar = false } else if isFullScreen { toggleFullScreen() } else { showGuide() }
        case 51: playPrevious()                      // backspace = last channel
        case 49: player.togglePause()                // space
        default:
            switch chars {
            case "g": showGuide()
            case "i": showInfoBar ? (showInfoBar = false) : flashInfoBar()
            case "m": player.isMuted.toggle()
            case "r": toggleRecording()
            case "l": playPrevious()
            case "f": toggleFullScreen()
            case "=", "+": player.volume = min(130, player.volume + 5)
            case "-": player.volume = max(0, player.volume - 5)
            default: return false
            }
        }
        return true
    }

    private func handleListKey(_ e: NSEvent) -> Bool {
        let groups = library.groups
        switch e.keyCode {
        case 126:
            if channelListFocusGroups { listGroupSelection = max(0, listGroupSelection - 1) }
            else { listSelection = max(0, listSelection - 1) }
        case 125:
            if channelListFocusGroups { listGroupSelection = min(groups.count - 1, listGroupSelection + 1) }
            else { listSelection = min(groupChannels.count - 1, listSelection + 1) }
        case 123: channelListFocusGroups = true
        case 124:
            if channelListFocusGroups, groups.indices.contains(listGroupSelection) {
                selectedGroup = groups[listGroupSelection].name
                listSelection = 0
            }
            channelListFocusGroups = false
        case 36, 76:
            if channelListFocusGroups, groups.indices.contains(listGroupSelection) {
                selectedGroup = groups[listGroupSelection].name
                listSelection = 0
                channelListFocusGroups = false
            } else if groupChannels.indices.contains(listSelection) {
                play(groupChannels[listSelection])
                showChannelList = false
            }
        case 53, 51: showChannelList = false
        default:
            if e.charactersIgnoringModifiers?.lowercased() == "f", groupChannels.indices.contains(listSelection) {
                library.toggleFavourite(groupChannels[listSelection])
                return true
            }
            return false
        }
        return true
    }

    func enterDigit(_ d: Int) {
        numberEntry += String(d)
        numberTimer?.invalidate()
        numberTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.commitNumber() }
        }
    }

    private func commitNumber() {
        defer { numberEntry = "" }
        guard let n = Int(numberEntry), let ch = library.channels.first(where: { $0.number == n }) else { return }
        if screen == .guide {
            if let i = groupChannels.firstIndex(of: ch) { guideRow = i }
            else { selectedGroup = ChannelGroup.all; guideRow = library.channels.firstIndex(of: ch) ?? 0 }
            schedulePreview()
        } else {
            play(ch)
        }
    }
}
